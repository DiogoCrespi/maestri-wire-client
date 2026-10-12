import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_chat.dart';
import '../../core/network/api_terminal_actions.dart';
import '../../core/network/terminal_stream.dart';
import 'roles_screen.dart';
import '../../core/terminal/agent_health.dart';
import '../../core/terminal/agent_interaction.dart';
import '../../core/terminal/input_history.dart';
import '../../core/network/terminal_chat_stream.dart';
import '../../core/network/terminal_text.dart';
import '../../models/chat_attachment.dart';
import '../../models/chat_mention.dart';
import '../../models/terminal_chat.dart';
import '../../models/canvas_node.dart';
import '../../state/wire_controller.dart';
import '../widgets/chat_entry_bubble.dart';
import '../widgets/chat_pending_attachments.dart';
import '../widgets/chat_thread_bar.dart';
import '../widgets/mention_picker.dart';

/// Tela cheia de Terminal Interativo com streaming PTY, chat estruturado do host
/// (capability `terminalChat`) e barra de atalhos rápidos.
class TerminalFullscreen extends StatefulWidget {
  final CanvasNode node;
  final WireController controller;

  const TerminalFullscreen({
    Key? key,
    required this.node,
    required this.controller,
  }) : super(key: key);

  @override
  State<TerminalFullscreen> createState() => _TerminalFullscreenState();
}

class _TerminalFullscreenState extends State<TerminalFullscreen> {
  late TerminalStream _stream;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  // Mensagens enviadas, recuperadas com ↑/↓ no campo
  final InputHistory _history = InputHistory();
  final ScrollController _scrollController = ScrollController();
  final TerminalConversation _buffer = TerminalConversation();

  // Chat estruturado do host. `_chat == null` quando o host não tem terminalChat.
  ChatSnapshot? _chat;
  TerminalChatStream? _chatStream;
  // Depois do primeiro snapshot do socket, respostas HTTP não sobrescrevem mais o estado
  bool _gotSocketSnapshot = false;
  bool _loadingOlder = false;
  Timer? _olderTimeout;
  double? _extentBeforeOlder;
  bool _markingRead = false;
  bool _sending = false;
  bool _uploading = false;
  String? _lastEntryId;
  final List<ChatAttachment> _pending = [];

  // Seletor de `@`: alvos do host carregados uma vez; arquivos por consulta (com debounce)
  List<ChatMention>? _mentions;
  bool _mentionsLoading = false;
  List<ChatFileEntry> _files = const [];
  bool _filesLoading = false;
  String? _filesError;
  String? _mentionToken; // texto depois do '@' no fim do campo; null quando não há
  Timer? _filesDebounce;

  String get _terminalId => widget.node.terminalId ?? widget.node.id;
  bool get _chatOn => _chat?.enabled == true;

  bool get _isAgent =>
      widget.node.title.toLowerCase().contains('codex') ||
      widget.node.title.toLowerCase().contains('claude') ||
      (widget.node.rawData['terminal']?['agentType'] != null &&
          widget.node.rawData['terminal']?['agentType'] != 'generic_shell');

  @override
  void initState() {
    super.initState();
    // Abre já digitável: o campo recebe o foco assim que a tela aparece
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });

    // Carrega o histórico recente do nó para visualização imediata
    final preview = widget.node.previewText;
    if (preview != null && preview.isNotEmpty) {
      _buffer.addText(preview.split('\n').join('\r\n'));
      _buffer.addText('\r\n');
    }

    _stream = TerminalStream(
      client: widget.controller.client,
      terminalId: _terminalId,
    );

    _stream.output.listen((data) {
      if (mounted) {
        setState(() => _buffer.addText(data));
        _scrollToBottom();
      }
    });

    _stream.geometry.listen((g) {
      if (mounted) {
        setState(() => _buffer.resize(rows: g.rows, cols: g.cols));
      }
    });

    _stream.connect();

    _chatStream = TerminalChatStream(
      client: widget.controller.client,
      terminalId: _terminalId,
    );
    _chatStream!.snapshots.listen((snap) => _onSnapshot(snap));
    _chatStream!.connect();
    _loadInitialChat();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _errorText(Object e) => e is TerminalActionException ? e.message : e.toString();

  void _showSnack(String text, {int seconds = 2}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: Duration(seconds: seconds)),
    );
  }

  /// Executa uma ação de escrita e mostra o erro do host, se houver.
  Future<void> _run(Future<void> Function() action, {required String failMessage}) async {
    try {
      await action();
    } catch (e) {
      _showSnack('$failMessage: ${_errorText(e)}', seconds: 3);
    }
  }

  Future<bool> _confirm(String title, String body, {String action = 'Confirmar'}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Text(body, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action, style: const TextStyle(color: AppColors.statusAlert)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Aplica um snapshot. Snapshots do socket são a fonte ordenada; um snapshot de
  /// HTTP só entra antes do primeiro do socket, para nunca sobrescrever um mais novo.
  void _onSnapshot(ChatSnapshot snap, {bool fromSocket = true}) {
    if (!mounted) return;
    if (fromSocket) _gotSocketSnapshot = true;
    if (!fromSocket && _gotSocketSnapshot) return;

    final prev = _chat;
    final lastId = snap.entries.isEmpty ? null : snap.entries.last.id;
    final grew = lastId != null && lastId != _lastEntryId;
    _lastEntryId = lastId;
    final wasLoadingOlder = _loadingOlder;
    final extentBefore = _extentBeforeOlder;
    _extentBeforeOlder = null;

    setState(() {
      // Thread trocada: o anexo preparado era da conversa anterior
      if (prev != null && prev.conversationId != snap.conversationId) _pending.clear();
      _chat = snap;
      _loadingOlder = false;
      _olderTimeout?.cancel();
    });

    if (wasLoadingOlder && extentBefore != null) {
      // Entradas antigas entram no topo: mantém a posição de quem está lendo
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final pos = _scrollController.position;
        _scrollController.jumpTo(pos.pixels + (pos.maxScrollExtent - extentBefore));
      });
    } else if (grew) {
      _scrollToBottom();
    }

    if (snap.enabled && snap.unreadCount > 0) _markRead();
  }

  Future<void> _loadInitialChat() async {
    try {
      final json = await widget.controller.client.getTerminalChat(_terminalId);
      _onSnapshot(ChatSnapshot.fromJson(json), fromSocket: false);
    } catch (_) {
      // Host sem terminalChat (ou offline): a face de chat não existe para este terminal
      _chatStream?.disconnect();
    }
  }

  Future<void> _markRead() async {
    if (_markingRead) return;
    _markingRead = true;
    try {
      await widget.controller.client.markChatRead(_terminalId);
    } catch (_) {
      // Sem marca de leitura: a próxima atualização tenta de novo
    } finally {
      _markingRead = false;
    }
  }

  // ── Modo chat, threads, histórico ──────────────────────────────────────────

  Future<void> _toggleChat() async {
    final chat = _chat;
    if (chat == null) return;
    // A resposta do PUT pode vir antes da mudança; o estado vem pelo socket
    await _run(() => widget.controller.client
        .setChatEnabled(_terminalId, enabled: !chat.enabled),
        failMessage: 'Não foi possível mudar o modo chat');
  }

  Future<void> _toggleShellWindow() async {
    final chat = _chat;
    if (chat == null) return;
    await _run(() => widget.controller.client.setChatEnabled(
          _terminalId,
          enabled: chat.enabled,
          showsShellWindow: !chat.showsShellWindow,
        ), failMessage: 'Não foi possível mudar a janela do shell');
  }

  Future<void> _selectThread(int slot) async {
    await _run(() => widget.controller.client.selectChatThread(_terminalId, slot),
        failMessage: 'Não foi possível trocar de thread');
  }

  Future<void> _confirmClearThread(int slot) async {
    final ok = await _confirm(
      'Limpar thread ${slot + 1}',
      'As mensagens dessa thread saem do histórico. A memória do agente não muda.',
      action: 'Limpar',
    );
    if (!ok) return;
    await _run(() => widget.controller.client.clearChatThread(_terminalId, slot),
        failMessage: 'Thread não limpa');
  }

  Future<void> _clearChatHistory() async {
    final ok = await _confirm(
      'Limpar histórico do chat',
      'A transcrição e os anexos retidos saem do host. A memória do agente não muda.',
      action: 'Limpar',
    );
    if (!ok) return;
    await _run(() => widget.controller.client.clearChatHistory(_terminalId),
        failMessage: 'Histórico não limpo (há um turno em andamento?)');
  }

  Future<void> _confirmDeleteEntry(ChatEntry entry) async {
    final ok = await _confirm('Excluir mensagem', 'Esta entrada sai do histórico do chat.',
        action: 'Excluir');
    if (!ok) return;
    await _run(() => widget.controller.client.deleteChatEntry(_terminalId, entry.id),
        failMessage: 'Mensagem não excluída');
  }

  /// Botão "carregar mais" no topo: pede a página anterior à entrada mais antiga.
  Future<void> _loadOlder() async {
    final chat = _chat;
    if (chat == null || _loadingOlder || !chat.hasOlderOnRecord || chat.entries.isEmpty) return;
    setState(() => _loadingOlder = true);
    _extentBeforeOlder =
        _scrollController.hasClients ? _scrollController.position.maxScrollExtent : null;
    _olderTimeout?.cancel();
    // Sem resposta do socket em 8 s, libera o botão de novo
    _olderTimeout = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _loadingOlder = false);
    });
    try {
      final ok = await widget.controller.client.requestOlderChat(
        terminalId: _terminalId,
        conversationId: chat.conversationId,
        beforeEntryId: chat.entries.first.id,
      );
      if (!ok && mounted) setState(() => _loadingOlder = false);
    } catch (e) {
      if (mounted) setState(() => _loadingOlder = false);
      _showSnack('Histórico anterior indisponível: ${_errorText(e)}', seconds: 3);
    }
  }

  void _onChatMenu(String value) {
    switch (value) {
      case 'seen':
        _run(() => widget.controller.client.markTerminalSeen(_terminalId),
            failMessage: 'Não foi possível marcar como visto');
      case 'shell':
        _toggleShellWindow();
      case 'clear':
        _clearChatHistory();
    }
  }

  // ── Anexos ─────────────────────────────────────────────────────────────────

  static String _mimeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
      case 'md':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  static const int _maxAttachmentBytes = 8 * 1024 * 1024;

  Future<void> _attach() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxAttachmentBytes) {
        _showSnack('Anexo acima de 8 MiB', seconds: 3);
        return;
      }
      await _run(() async {
        final att = await widget.controller.client.uploadChatAttachment(
          _terminalId,
          bytes: bytes,
          fileName: picked.name,
          mimeType: picked.mimeType ?? _mimeFor(picked.name),
        );
        if (mounted) setState(() => _pending.add(att));
      }, failMessage: 'Anexo não enviado');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePending(ChatAttachment att) async {
    setState(() => _pending.remove(att));
    await _run(() => widget.controller.client.discardStagedAttachment(_terminalId, att.attachmentId),
        failMessage: 'Anexo não removido');
  }

  // ── Menções com @ ──────────────────────────────────────────────────────────

  void _onInputChanged() {
    _syncMentionToken();
    setState(() {});
  }

  /// Atualiza o token de `@` do fim do campo e dispara as buscas necessárias.
  void _syncMentionToken() {
    final last = _inputController.text.split(RegExp(r'\s')).last;
    final token = last.startsWith('@') ? last.substring(1) : null;
    if (token == null || !(_chatOn || _isAgent)) {
      _mentionToken = null;
      _filesDebounce?.cancel();
      return;
    }
    if (token == _mentionToken) return;
    _mentionToken = token;
    if (_mentions == null && !_mentionsLoading) _loadMentions();
    _filesDebounce?.cancel();
    _filesDebounce = Timer(const Duration(milliseconds: 200), () => _loadFiles(token));
  }

  Future<void> _loadMentions() async {
    _mentionsLoading = true;
    try {
      final list = await widget.controller.client.getChatMentions(_terminalId);
      if (mounted) setState(() => _mentions = list);
    } catch (_) {
      if (mounted) setState(() => _mentions = const []);
    } finally {
      _mentionsLoading = false;
    }
  }

  /// Arquivos do terminal: `@pasta/termo` busca dentro de `pasta`; sem `/`, busca na raiz.
  Future<void> _loadFiles(String token) async {
    final slash = token.lastIndexOf('/');
    final scope = slash >= 0 ? token.substring(0, slash) : '';
    final query = slash >= 0 ? token.substring(slash + 1) : token;
    if (!mounted) return;
    setState(() {
      _filesLoading = true;
      _filesError = null;
    });
    try {
      final listing = await widget.controller.client
          .getTerminalFiles(_terminalId, query: query, scope: scope, limit: 60);
      if (!mounted || _mentionToken != token) return; // resposta de um token antigo
      setState(() {
        _files = listing.entries;
        _filesLoading = false;
      });
    } catch (e) {
      if (!mounted || _mentionToken != token) return;
      setState(() {
        _files = const [];
        _filesLoading = false;
        _filesError = 'Arquivos indisponíveis: ${_errorText(e)}';
      });
    }
  }

  List<ChatMention> get _visibleMentions {
    final token = _mentionToken;
    final all = _mentions ?? const <ChatMention>[];
    if (token == null || token.contains('/')) return const [];
    final q = token.toLowerCase();
    return all
        .where((m) =>
            q.isEmpty ||
            m.name.toLowerCase().contains(q) ||
            (m.tokenName ?? '').toLowerCase().contains(q))
        .take(12)
        .toList();
  }

  /// Troca o `@token` do fim do campo por [insert]. Pasta fica aberta para navegar.
  void _insertToken(String insert, {bool trailingSpace = true}) {
    final text = _inputController.text;
    final token = _mentionToken ?? '';
    final base = text.substring(0, text.length - token.length - 1);
    final value = '$base$insert${trailingSpace ? ' ' : ''}';
    _mentionToken = null;
    _inputController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _syncMentionToken();
    setState(() {});
  }

  void _onFilePicked(ChatFileEntry f) {
    _insertToken('@${f.relativePath}${f.isDirectory ? '/' : ''}', trailingSpace: !f.isDirectory);
  }

  // ── Entrada ────────────────────────────────────────────────────────────────

  /// Escolhe uma opção de menu: navega com as setas até ela e confirma com Enter.
  /// Opções y/n são respondidas com a própria tecla.
  void _pickChoice(ChoicePrompt choice, ChoiceOption option) {
    _stream.sendControl(choiceKeySequence(choice, option));
  }

  /// ↑/↓ no campo: recupera mensagens enviadas (a mais recente primeiro).
  KeyEventResult _onInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    String? text;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      text = _history.previous(_inputController.text);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      text = _history.next();
    }
    if (text == null) return KeyEventResult.ignored;
    _setInput(text);
    return KeyEventResult.handled;
  }

  void _setInput(String text) {
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncMentionToken();
    setState(() {});
  }

  Future<void> _sendCurrentInput() async {
    final text = _inputController.text.trim();
    final attachments = List<ChatAttachment>.of(_pending);
    if (text.isEmpty && attachments.isEmpty) return;
    if (_sending) return;

    // Shell sem chat e sem anexo: bytes brutos UTF-8 direto ao PTY, como antes
    if (attachments.isEmpty && !_chatOn && !_isAgent) {
      _history.add(text);
      _stream.sendInput('$text\n');
      _inputController.clear();
      _syncMentionToken();
      setState(() {});
      _scrollToBottom();
      return;
    }

    if (text.isNotEmpty) _history.add(text);
    final segments = <PromptSegment>[
      if (text.isNotEmpty) TextSegment(text),
      for (final a in attachments) AttachmentSegment(a.attachmentId),
    ];
    setState(() => _sending = true);
    try {
      await widget.controller.client.sendChatPrompt(
        _terminalId,
        segments,
        clientMessageId: const Uuid().v4(),
      );
      if (!mounted) return;
      setState(() {
        _inputController.clear();
        _mentionToken = null;
        _pending.removeWhere((a) => attachments.any((x) => x.attachmentId == a.attachmentId));
        if (!_chatOn && text.isNotEmpty) _buffer.addUserMessage(text);
      });
      _scrollToBottom();
    } catch (e) {
      _showSnack('Mensagem não enviada: ${_errorText(e)}', seconds: 3);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _approveAction() async {
    await widget.controller.client.approveTerminal(_terminalId);
    _stream.sendInput('y\n');
    _showSnack('Ação aprovada com sucesso!', seconds: 1);
  }

  void _rejectAction() async {
    await widget.controller.client.rejectTerminal(_terminalId);
    _stream.sendInput('n\n');
    _showSnack('Ação rejeitada.', seconds: 1);
  }

  void _focusHost() {
    _run(() => widget.controller.client.focusTerminal(_terminalId), failMessage: 'Não foi possível focar no host');
  }

  void _copyAllOutput() {
    if (!_buffer.isEmpty) {
      final allText = _buffer.plainText;
      Clipboard.setData(ClipboardData(text: allText));
      _showSnack('Todo o histórico do terminal foi copiado!');
    }
  }

  @override
  void dispose() {
    _inputFocus.dispose();
    _filesDebounce?.cancel();
    _olderTimeout?.cancel();
    _chatStream?.dispose();
    _stream.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    return Scaffold(
      backgroundColor: AppColors.terminalBg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(
          children: [
            Icon(
              _isAgent ? Icons.psychology_rounded : Icons.terminal_rounded,
              size: 16,
              color: AppColors.textAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.node.title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_isAgent) ...[
            TextButton.icon(
              icon: const Icon(Icons.check_rounded, size: 14, color: AppColors.statusActive),
              label: const Text('Aprovar', style: TextStyle(color: AppColors.statusActive, fontSize: 12)),
              onPressed: _approveAction,
            ),
          ],
          if (chat != null)
            IconButton(
              icon: Icon(
                chat.enabled ? Icons.forum_rounded : Icons.forum_outlined,
                size: 20,
                color: chat.enabled ? AppColors.neonViolet : null,
              ),
              tooltip: chat.enabled ? 'Desligar modo chat' : 'Ligar modo chat',
              onPressed: _toggleChat,
            ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong_outlined, size: 20),
            tooltip: 'Focar no host',
            onPressed: _focusHost,
          ),
          if (_isAgent)
            IconButton(
              icon: const Icon(Icons.badge_outlined, size: 20),
              tooltip: 'Responsabilidade',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RolesScreen(
                    client: widget.controller.client,
                    terminalId: _terminalId,
                    terminalName: widget.node.title,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.copy_all_rounded, size: 20),
            tooltip: 'Copiar Tudo',
            onPressed: _copyAllOutput,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, size: 20),
            tooltip: 'Limpar Tela',
            onPressed: () => setState(_buffer.clear),
          ),
          if (chat != null)
            PopupMenuButton<String>(
              tooltip: 'Chat',
              onSelected: _onChatMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'seen', child: Text('Marcar como visto')),
                if (chat.enabled)
                  PopupMenuItem(
                    value: 'shell',
                    child: Text(chat.showsShellWindow
                        ? 'Ocultar janela do shell'
                        : 'Mostrar janela do shell'),
                  ),
                if (chat.enabled)
                  PopupMenuItem(
                    value: 'clear',
                    enabled: chat.canClear,
                    child: const Text('Limpar histórico do chat'),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Aviso quando o agente não subiu (caiu para shell) ou falta o ambiente Maestro
            if (_isAgent) _buildHealthBanner(),

            // Threads do chat: só quando o host as informa
            if (_chatOn && chat?.threads != null)
              ChatThreadBar(
                threads: chat!.threads!,
                onSelect: _selectThread,
                onClear: _confirmClearThread,
              ),

            // Conversa: chat estruturado quando ligado, senão a saída crua do PTY
            Expanded(
              child: Container(
                color: AppColors.terminalBg,
                child: _buildConversation(),
              ),
            ),

            // Barra de Atalhos Rápidos (Ctrl+C, Tab, Esc, etc.)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: AppColors.surfaceElevated,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_isAgent) ...[
                    _shortcutButton('✓ Aprovar (y)', _approveAction),
                    _shortcutButton('✗ Rejeitar (n)', _rejectAction),
                  ],
                  _shortcutButton('Ctrl+C', () => _stream.sendControl('\x03')),
                  _shortcutButton('Tab', () => _stream.sendControl('\t')),
                  _shortcutButton('/', () {
                    _inputController.text = '/';
                    _inputController.selection = const TextSelection.collapsed(offset: 1);
                    _syncMentionToken();
                    setState(() {});
                  }),
                  _shortcutButton('?', () {
                    // Com o campo vazio, '?' vai direto ao agente (ex.: atalhos do Codex)
                    if (_inputController.text.isEmpty) {
                      _stream.sendInput('?');
                    } else {
                      _inputController.text += '?';
                      setState(() {});
                    }
                  }),
                  _shortcutButton('Esc', () => _stream.sendControl('\x1b')),
                  _shortcutButton('Enter', () => _stream.sendControl('\r')),
                  _shortcutButton('▲ Up', () => _stream.sendControl('\x1b[A')),
                  _shortcutButton('▼ Down', () => _stream.sendControl('\x1b[B')),
                ],
              ),
            ),

            // Seletor de @ (enquanto se digita uma menção), senão escolhas e sugestões do agente
            if (_mentionToken != null && (_chatOn || _isAgent))
              _buildMentionPanel()
            else if (_isAgent)
              _buildInteractionPanel(),

            // Anexos preparados para o próximo envio
            if (_chatOn) ChatPendingAttachments(items: _pending, onRemove: _removePending),

            // Campo de Entrada do Usuário
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  if (_chatOn)
                    IconButton(
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file_rounded, size: 20),
                      tooltip: 'Anexar imagem',
                      onPressed: _uploading || _sending ? null : _attach,
                    ),
                  const Text('❯ ',
                      style: TextStyle(
                          color: AppColors.statusActive,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  Expanded(
                    child: Focus(
                      onKeyEvent: _onInputKey,
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocus,
                        autofocus: true,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Digite um comando ou prompt... (@ menciona)',
                          hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => _onInputChanged(),
                        onSubmitted: (_) => _sendCurrentInput(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    color: AppColors.neonViolet,
                    onPressed: _sending ? null : _sendCurrentInput,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _agentLabel {
    switch (widget.node.rawData['terminal']?['agentType']) {
      case 'antigravity_cli':
        return 'Antigravity';
      case 'claude_code':
        return 'Claude Code';
      case 'codex':
        return 'Codex';
      case 'open_code':
        return 'OpenCode';
      default:
        return widget.node.title;
    }
  }

  Widget _buildHealthBanner() {
    final lines = _buffer.plainText.split('\n');
    final issue = detectAgentIssue(lines);
    if (!issue.hasIssue) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2110),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0A030)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFE0A030)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              agentIssueMessage(issue, agentName: _agentLabel),
              style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversation() {
    final chat = _chat;
    if (_chatOn && chat != null) return _buildChatList(chat);
    final blocks = _buffer.blocks;
    if (blocks.isEmpty) {
      return const Center(
        child: Text(
          'Aguardando saída do terminal...',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: blocks.length,
      itemBuilder: (_, i) => _buildBlock(blocks[i]),
    );
  }

  Widget _buildChatList(ChatSnapshot chat) {
    final entries = chat.entries;
    final working = chat.isWorking;
    if (entries.isEmpty && !working) {
      return const Center(
        child: Text(
          'Nenhuma mensagem ainda.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: 1 + entries.length + (working ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == 0) return _buildLoadOlder(chat);
        final idx = i - 1;
        if (idx < entries.length) {
          final e = entries[idx];
          return ChatEntryBubble(
            entry: e,
            onLongPress: e.kind == ChatEntryKind.divider ? null : () => _confirmDeleteEntry(e),
          );
        }
        return const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(Icons.hourglass_top_rounded, size: 13, color: AppColors.textMuted),
              SizedBox(width: 6),
              Text('Trabalhando…',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.textMuted)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadOlder(ChatSnapshot chat) {
    if (!chat.hasOlderOnRecord) return const SizedBox.shrink();
    return Center(
      child: TextButton.icon(
        icon: const Icon(Icons.history_rounded, size: 16),
        label: Text(
          _loadingOlder ? 'Carregando…' : 'Carregar mensagens anteriores',
          style: const TextStyle(fontSize: 12),
        ),
        onPressed: _loadingOlder ? null : _loadOlder,
      ),
    );
  }

  Widget _buildBlock(TerminalBlock block) {
    switch (block.kind) {
      case TerminalBlockKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(left: 48, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.neonViolet.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              block.text,
              style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: AppColors.textPrimary),
            ),
          ),
        );
      case TerminalBlockKind.agent:
        return Container(
          margin: const EdgeInsets.only(right: 24, bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.psychology_rounded, size: 14, color: AppColors.textAccent),
                  SizedBox(width: 6),
                  Text('Agente',
                      style: TextStyle(
                          color: AppColors.textAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                block.text,
                style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: AppColors.textPrimary),
              ),
            ],
          ),
        );
      case TerminalBlockKind.status:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: SelectableText(
                  block.text,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        );
      case TerminalBlockKind.raw:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SelectableText(
            block.text,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        );
    }
  }

  Widget _buildMentionPanel() {
    return MentionPicker(
      mentions: _visibleMentions,
      files: _files,
      loadingFiles: _filesLoading,
      filesError: _filesError,
      onMention: (m) => _insertToken(m.insertText),
      onFile: _onFilePicked,
    );
  }

  /// Pergunta de escolha do agente (botões) ou sugestões de `/comando` para o texto digitado.
  Widget _buildInteractionPanel() {
    final lines = _buffer.screen.screenLines;
    final choice = detectChoicePrompt(lines);
    final suggestions = slashSuggestions(
      widget.node.rawData['terminal']?['agentType'] as String?,
      _inputController.text,
    );
    if (choice == null && suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (choice != null) ...[
            if (choice.question.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  choice.question,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in choice.options)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: o.isSelected ? AppColors.neonViolet : AppColors.textSecondary,
                      side: BorderSide(
                        color: o.isSelected ? AppColors.neonViolet : AppColors.border,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: () => _pickChoice(choice, o),
                    child: Text('${o.key}. ${o.label}', style: const TextStyle(fontSize: 12)),
                  ),
                OutlinedButton(
                  onPressed: () => _stream.sendControl('\r'),
                  child: const Text('Enter', style: TextStyle(fontSize: 12)),
                ),
                OutlinedButton(
                  onPressed: () => _stream.sendControl('\x1b'),
                  child: const Text('Esc', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
          if (choice != null && suggestions.isNotEmpty) const SizedBox(height: 10),
          if (suggestions.isNotEmpty) ...[
            const Text('Comandos', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in suggestions)
                  ActionChip(
                    label: Text(c, style: GoogleFonts.jetBrainsMono(fontSize: 12)),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.border),
                    onPressed: () {
                      _inputController.text = '$c ';
                      _inputController.selection =
                          TextSelection.collapsed(offset: _inputController.text.length);
                      _syncMentionToken();
                      setState(() {});
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _shortcutButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: AppColors.surfaceHover,
          foregroundColor: AppColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
