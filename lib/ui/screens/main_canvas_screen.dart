import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/mac_theme.dart';
import '../../models/canvas/connection.dart';
import '../../models/canvas/connection_kind.dart';
import '../../models/canvas_node.dart';
import '../../state/wire_controller.dart';
import '../canvas/infinite_canvas.dart';
import '../widgets/mac_window_bar.dart';
import '../widgets/workspace_sidebar.dart';
import 'note_screen.dart';
import 'note_stack_screen.dart';
import 'file_tree_screen.dart';
import 'roles_screen.dart';
import 'routines_screen.dart';
import '../widgets/floor_selector.dart';
import '../widgets/floor_actions.dart';
import '../../core/network/api_terminals.dart';
import '../../core/network/api_canvas.dart';
import '../../core/network/api_floors.dart';
import '../../core/network/api_terminal_actions.dart';
import '../widgets/create_terminal_sheet.dart';
import '../widgets/terminal_actions_sheet.dart';
import 'terminal_fullscreen.dart';
import 'pair_screen.dart';

/// Tela Principal do Canvas com layout responsivo para Android e Windows
class MainCanvasScreen extends StatefulWidget {
  final WireController controller;

  const MainCanvasScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<MainCanvasScreen> createState() => _MainCanvasScreenState();
}

class _MainCanvasScreenState extends State<MainCanvasScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Canvas do andar que está na tela (snapshot completo: nós, cordas, grupos, desenhos, abraçadeiras).
  CanvasSnapshot? _canvas;
  /// Capabilities do host (`/api/info`). Escritas e presença só aparecem quando anunciadas.
  Set<String> _capabilities = {};
  /// Nós selecionados para seleção múltipla.
  final Set<String> _selected = {};
  bool _selectMode = false;
  bool _fetchingCanvas = false;
  bool _fetchAgain = false;

  bool get _canWrite =>
      widget.controller.isOwner && _capabilities.contains('canvasWrites');

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _loadCapabilities();
    _fetchCanvas();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    _fetchCanvas();
  }

  Future<void> _loadCapabilities() async {
    try {
      final info = await widget.controller.client.getInfo();
      final caps = info['capabilities'];
      if (caps is List && mounted) {
        setState(() => _capabilities = {for (final c in caps) c.toString()});
      }
    } catch (_) {
      // Sem /api/info o canvas segue só de leitura; tenta de novo na próxima troca de feed
    }
  }

  /// Busca o canvas do andar que está na tela. Uma busca por vez; se chegar outra no meio, refaz.
  Future<void> _fetchCanvas() async {
    final ws = widget.controller.activeWorkspace;
    if (ws == null || widget.controller.client.authToken == null) return;
    if (_fetchingCanvas) {
      _fetchAgain = true;
      return;
    }
    _fetchingCanvas = true;
    try {
      do {
        _fetchAgain = false;
        final raw = await widget.controller.client.getFloorFeed(
          ws.id,
          floor: widget.controller.viewingFloor?.queryValue,
        );
        final canvasJson = raw['canvas'];
        if (canvasJson is Map<String, dynamic> && mounted) {
          final snapshot = CanvasSnapshot.fromJson(canvasJson);
          final ids = {for (final n in snapshot.nodes) n.id};
          setState(() {
            _canvas = snapshot;
            _selected.removeWhere((id) => !ids.contains(id));
          });
        }
        if (_capabilities.isEmpty) _loadCapabilities();
      } while (_fetchAgain && mounted);
    } catch (_) {
      // Falha passageira: o próximo aviso do controlador tenta de novo
    } finally {
      _fetchingCanvas = false;
    }
  }

  void _showError(Object e, String prefixo) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$prefixo: $e')),
    );
  }

  Future<bool> _confirm(String titulo, String corpo, {String acao = 'Confirmar'}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(titulo, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text(corpo, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(acao)),
        ],
      ),
    );
    return ok == true;
  }

  String? get _wsId => widget.controller.activeWorkspace?.id;

  /// Liga ou desliga um nó da seleção múltipla.
  void _toggleSelect(CanvasNode node) {
    setState(() {
      if (!_selected.remove(node.id)) _selected.add(node.id);
    });
  }

  /// Presença: diz ao host qual nó está aberto neste dispositivo (capability `presence`).
  void _sendPresence(String? nodeId) {
    if (!_capabilities.contains('presence')) return;
    widget.controller.feedSocket.sendJson(
      nodeId == null ? {'type': 'presence'} : {'type': 'presence', 'nodeId': nodeId},
    );
  }

  Future<void> _connectNodes(CanvasNode from, CanvasNode to) async {
    final ws = _wsId;
    if (ws == null || from.id == to.id) return;
    try {
      await widget.controller.client.createConnection(
        workspaceId: ws,
        fromNodeId: from.id,
        toNodeId: to.id,
      );
      await _fetchCanvas();
    } catch (e) {
      _showError(e, 'Não foi possível ligar');
    }
  }

  /// Toque num cabo: corta a corda. Pontas de connector são cortadas excluindo o connector.
  Future<void> _onCableTap(Connection cable) async {
    final ws = _wsId;
    if (ws == null) return;
    final nodes = {for (final n in (_canvas?.nodes ?? const <CanvasNode>[])) n.id: n};
    final fromNode = nodes[cable.fromNodeId];
    final toNode = nodes[cable.toNodeId];
    final isConnector = fromNode?.type == NodeType.connector || toNode?.type == NodeType.connector;
    if (cable.kind == ConnectionKind.crossFloor ||
        cable.kind == ConnectionKind.crossWorkspace ||
        isConnector) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Esta corda liga a um conector: exclua o conector para cortá-la'),
        ));
      }
      return;
    }
    final ok = await _confirm(
      'Desconectar cabo?',
      '${fromNode?.title ?? 'Origem'} deixa de estar ligado a ${toNode?.title ?? 'destino'}.',
      acao: 'Desconectar',
    );
    if (!ok) return;
    try {
      await widget.controller.client.deleteConnection(
        workspaceId: ws,
        fromNodeId: cable.fromNodeId,
        toNodeId: cable.toNodeId,
      );
      await _fetchCanvas();
    } catch (e) {
      _showError(e, 'Não foi possível desconectar');
    }
  }

  Future<void> _createText() async {
    final ws = widget.controller.activeWorkspace;
    if (ws == null) return;
    final nodes = _canvas?.nodes ?? const <CanvasNode>[];
    double x = 0;
    double y = 0;
    if (nodes.isNotEmpty) {
      x = nodes.map((n) => n.position.dx).reduce((a, b) => a < b ? a : b);
      y = nodes.map((n) => n.position.dy + n.size.height).reduce((a, b) => a > b ? a : b) + 40;
    }
    try {
      await widget.controller.client.createTextNode(workspaceId: ws.id, x: x, y: y, text: 'Texto');
      await _fetchCanvas();
    } catch (e) {
      _showError(e, 'Não foi possível criar o texto');
    }
  }

  /// Ações de um nó (toque longo). Escritas só para owner com `canvasWrites`.
  Future<void> _showNodeActions(CanvasNode node) async {
    final ws = _wsId;
    if (ws == null) return;
    final canWrite = _canWrite;
    final isTerminal = node.type == NodeType.terminal;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(node.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            ),
            if (isTerminal)
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Ações do terminal'),
                onTap: () => Navigator.pop(ctx, 'terminal'),
              ),
            if (canWrite) ...[
              // Blocos de texto e plaquinhas de conector não são renomeáveis no host (400)
              if (node.type != NodeType.text && node.type != NodeType.connector)
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Renomear'),
                  onTap: () => Navigator.pop(ctx, 'rename'),
                ),
              if (node.type != NodeType.connector)
                ListTile(
                  leading: Icon(node.isLocked ? Icons.lock_open_rounded : Icons.lock_rounded),
                  title: Text(node.isLocked ? 'Destravar' : 'Travar'),
                  onTap: () => Navigator.pop(ctx, 'lock'),
                ),
              if (node.type != NodeType.connector)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Duplicar'),
                  onTap: () => Navigator.pop(ctx, 'duplicate'),
                ),
              if (node.groupId != null)
                ListTile(
                  leading: const Icon(Icons.workspaces_outline),
                  title: const Text('Desagrupar'),
                  onTap: () => Navigator.pop(ctx, 'ungroup'),
                ),
              if (_capabilities.contains('nodeFocus'))
                ListTile(
                  leading: const Icon(Icons.center_focus_strong_rounded),
                  title: const Text('Focar no host'),
                  onTap: () => Navigator.pop(ctx, 'focus'),
                ),
            ],
            ListTile(
              leading: const Icon(Icons.check_box_outline_blank_rounded),
              title: const Text('Selecionar'),
              onTap: () => Navigator.pop(ctx, 'select'),
            ),
            if (canWrite)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.statusAlert),
                title: const Text('Excluir', style: TextStyle(color: AppColors.statusAlert)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final client = widget.controller.client;
    try {
      switch (action) {
        case 'terminal':
          await _manageTerminal(node);
        case 'select':
          setState(() {
            _selectMode = true;
            _selected.add(node.id);
          });
        case 'rename':
          final name = await _askText('Renomear', node.title);
          if (name == null || name.trim().isEmpty) return;
          await client.renameNode(workspaceId: ws, nodeId: node.id, name: name.trim());
        case 'lock':
          await client.setNodeLocked(workspaceId: ws, nodeId: node.id, locked: !node.isLocked);
        case 'duplicate':
          await client.duplicateNode(workspaceId: ws, nodeId: node.id);
        case 'ungroup':
          await client.ungroup(workspaceId: ws, nodeIds: [node.id]);
        case 'focus':
          await client.focusNode(workspaceId: ws, nodeId: node.id);
        case 'delete':
          final ok = await _confirm('Excluir "${node.title}"?',
              'O nó sai do canvas do host. Essa ação não pode ser desfeita daqui.',
              acao: 'Excluir');
          if (!ok) return;
          await client.deleteNode(workspaceId: ws, nodeId: node.id);
          _selected.remove(node.id);
      }
      await _fetchCanvas();
    } catch (e) {
      _showError(e, 'Não foi possível concluir');
    }
  }

  Future<String?> _askText(String titulo, String inicial) async {
    final controller = TextEditingController(text: inicial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(titulo, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Salvar')),
        ],
      ),
    );
  }

  /// Exclui a seleção (um nó: exclusão simples; vários: uma única requisição de lote).
  Future<void> _deleteSelected() async {
    final ws = _wsId;
    if (ws == null || _selected.isEmpty) return;
    final ids = _selected.toList();
    final ok = await _confirm(
      'Excluir ${ids.length} ${ids.length == 1 ? 'nó' : 'nós'}?',
      'Os nós selecionados saem do canvas do host.',
      acao: 'Excluir',
    );
    if (!ok) return;
    try {
      if (ids.length == 1) {
        await widget.controller.client.deleteNode(workspaceId: ws, nodeId: ids.first);
      } else {
        await widget.controller.client.deleteNodes(workspaceId: ws, nodeIds: ids);
      }
      setState(() {
        _selected.clear();
        _selectMode = false;
      });
      await _fetchCanvas();
    } catch (e) {
      _showError(e, 'Não foi possível excluir');
    }
  }

  Future<void> _groupSelected() async {
    final ws = _wsId;
    if (ws == null || _selected.length < 2) return;
    try {
      await widget.controller.client.createGroup(workspaceId: ws, nodeIds: _selected.toList());
      setState(() {
        _selected.clear();
        _selectMode = false;
      });
      await _fetchCanvas();
    } catch (e) {
      _showError(e, 'Não foi possível agrupar');
    }
  }

  Future<void> _ungroupSelected() async {
    final ws = _wsId;
    if (ws == null || _selected.isEmpty) return;
    try {
      await widget.controller.client.ungroup(workspaceId: ws, nodeIds: _selected.toList());
      await _fetchCanvas();
    } catch (e) {
      _showError(e, 'Não foi possível desagrupar');
    }
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  Widget _selectionBar() {
    final n = _selected.length;
    final groupedAny = (_canvas?.nodes ?? const <CanvasNode>[])
        .any((node) => _selected.contains(node.id) && node.groupId != null);
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: MacTheme.glassCardDecoration(borderRadius: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  n == 0 ? 'Toque nos nós' : '$n selecionado${n == 1 ? '' : 's'}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              if (_canWrite && n >= 2 && _capabilities.contains('nodeGroups'))
                IconButton(
                  tooltip: 'Agrupar',
                  icon: const Icon(Icons.workspaces_rounded, size: 20),
                  onPressed: _groupSelected,
                ),
              if (_canWrite && groupedAny && _capabilities.contains('nodeGroups'))
                IconButton(
                  tooltip: 'Desagrupar',
                  icon: const Icon(Icons.workspaces_outline, size: 20),
                  onPressed: _ungroupSelected,
                ),
              if (_canWrite && n > 0)
                IconButton(
                  tooltip: 'Excluir',
                  color: AppColors.statusAlert,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: _deleteSelected,
                ),
              IconButton(
                tooltip: 'Sair da seleção',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: _exitSelectMode,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPromptComposer() {
    final textController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: MacTheme.glassCardDecoration(borderRadius: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Novo Prompt para Agente',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppColors.textMuted,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: textController,
                  maxLines: 4,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Escreva a instrução para os agentes orquestrarem...',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    final prompt = textController.text.trim();
                    if (prompt.isNotEmpty &&
                        widget.controller.activeWorkspace != null &&
                        widget.controller.nodes.isNotEmpty) {
                      final terminalNode = widget.controller.nodes.firstWhere(
                        (n) => n.type == NodeType.terminal,
                        orElse: () => widget.controller.nodes.first,
                      );
                      widget.controller.client.sendPrompt(
                        workspaceId: widget.controller.activeWorkspace!.id,
                        terminalId: terminalNode.terminalId ?? terminalNode.id,
                        prompt: prompt,
                      );
                    }
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Disparar para Agentes'),
                  style: MacTheme.macPillButtonStyle(isPrimary: true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPortalModal(CanvasNode node) {
    final portalData = node.rawData['portal'] as Map<String, dynamic>?;
    final portalId = portalData?['portalId'] ?? node.id;
    final url = portalData?['currentURL'] ??
        portalData?['url'] ??
        node.rawData['subtitle'] ??
        'https://${node.title}';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: MacTheme.glassCardDecoration(borderRadius: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.neonCobalt.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.language_rounded,
                        size: 20, color: AppColors.neonCobalt),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          url,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textMuted,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 14, color: AppColors.statusActive),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Navegador headless ativo no servidor Linux (DCX)',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await widget.controller.client.reloadPortal(portalId);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Portal recarregado no servidor!')),
                          );
                        }
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Recarregar'),
                      style: MacTheme.macPillButtonStyle(isPrimary: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await widget.controller.client.backPortal(portalId);
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Voltar'),
                    style: MacTheme.macPillButtonStyle(isPrimary: false),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Cria uma nota abaixo do conteúdo atual do canvas e a abre para editar
  Future<void> _createNote() async {
    final ws = widget.controller.activeWorkspace;
    final nodes = _canvas?.nodes ?? const <CanvasNode>[];
    if (ws == null) return;
    double x = 0;
    double y = 0;
    if (nodes.isNotEmpty) {
      x = nodes.map((n) => n.position.dx).reduce((a, b) => a < b ? a : b);
      y = nodes.map((n) => n.position.dy + n.size.height).reduce((a, b) => a > b ? a : b) + 40;
    }
    try {
      final id = await widget.controller.client.createNote(
        workspaceId: ws.id,
        x: x,
        y: y,
      );
      await widget.controller.refreshFeed();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NoteScreen(
            client: widget.controller.client,
            workspaceId: ws.id,
            nodeId: id,
            title: 'Nova nota',
          ),
        ),
      );
      if (mounted) widget.controller.refreshFeed();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível criar a nota: $e')),
      );
    }
  }

  /// Salva no host a nova posição de um nó arrastado
  Future<void> _moveNode(CanvasNode node) async {
    final ws = widget.controller.activeWorkspace;
    if (ws == null) return;
    try {
      await widget.controller.client.moveNode(
        workspaceId: ws.id,
        nodeId: node.id,
        x: node.position.dx,
        y: node.position.dy,
        width: node.size.width,
        height: node.size.height,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Posição não salva no host: $e')),
        );
      }
    }
  }

  /// Cria um terminal (preset + nome) abaixo do conteúdo do canvas
  Future<void> _createTerminal() async {
    final ws = widget.controller.activeWorkspace;
    if (ws == null) return;
    final client = widget.controller.client;
    final nodes = widget.controller.nodes;
    double x = 0;
    double y = 0;
    if (nodes.isNotEmpty) {
      x = nodes.map((n) => n.position.dx).reduce((a, b) => a < b ? a : b);
      y = nodes.map((n) => n.position.dy + n.size.height).reduce((a, b) => a > b ? a : b) + 40;
    }
    try {
      final presets = widget.controller.presets.isNotEmpty
          ? widget.controller.presets
          : await client.listPresets();
      if (!mounted) return;
      await showCreateTerminalSheet(
        context,
        presets: presets,
        onCreate: (presetId, name, maestroMode) async {
          try {
            await client.createTerminal(
              workspaceId: ws.id,
              presetId: presetId,
              name: name,
              x: x,
              y: y,
              maestroMode: maestroMode,
            );
            await widget.controller.refreshFeed();
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Não foi possível criar o terminal: $e')),
              );
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível listar os presets: $e')),
        );
      }
    }
  }

  /// Ações de um terminal (Maestro, conectar, encerrar, excluir); toque longo no card
  Future<void> _manageTerminal(CanvasNode node) async {
    final ws = widget.controller.activeWorkspace;
    final terminalId = node.terminalId;
    if (ws == null || terminalId == null) return;
    final client = widget.controller.client;
    try {
      final settings = await client.getTerminalSettings(terminalId);
      if (!mounted) return;
      final peers = [
        for (final n in widget.controller.nodes)
          if (n.type == NodeType.terminal && n.id != node.id)
            (nodeId: n.id, title: n.title),
      ];
      await showTerminalActionsSheet(
        context,
        client: client,
        workspaceId: ws.id,
        terminalId: terminalId,
        nodeId: node.id,
        title: node.title,
        maestroMode: settings.maestroMode,
        isOwner: widget.controller.isOwner,
        otherNodes: peers,
        onChanged: () => widget.controller.refreshFeed(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir as ações: $e')),
        );
      }
    }
  }

  void _openRoutines() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoutinesScreen(
          client: widget.controller.client,
          canWrite: widget.controller.isOwner,
        ),
      ),
    );
  }

  void _openRoles() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RolesScreen(client: widget.controller.client),
      ),
    );
  }

  Future<void> _openFloors() {
    final controller = widget.controller;
    return FloorSelector.show(
      context,
      floors: controller.floors,
      viewingFloor: controller.viewingFloor?.queryValue,
      onView: (f) => controller.viewFloor(f),
      onActivate: controller.isOwner ? (f) => controller.activateFloor(f) : null,
      onCreate: controller.isOwner ? () => createFloorFlow(context, controller) : null,
      onManage: controller.isOwner ? (f) => manageFloorFlow(context, controller, f) : null,
    );
  }

  /// Abre o nó e avisa o host de presença (nó aberto enquanto a tela estiver nele).
  Future<void> _openTerminalFullscreen(CanvasNode node) async {
    _sendPresence(node.id);
    try {
      await _openNode(node);
    } finally {
      _sendPresence(null);
    }
  }

  Future<void> _openNode(CanvasNode node) async {
    if (node.type == NodeType.text ||
        node.type == NodeType.file ||
        node.type == NodeType.link ||
        node.type == NodeType.connector ||
        node.type == NodeType.unknown) {
      // Sem tela própria por enquanto: a seleção e as ações do nó cuidam dele
      return;
    }
    if (node.type == NodeType.portal) {
      _showPortalModal(node);
      return;
    }
    final ws = widget.controller.activeWorkspace;
    if (node.type == NodeType.noteStack) {
      if (ws == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NoteStackScreen(
            client: widget.controller.client,
            workspaceId: ws.id,
            stackNodeId: node.id,
            title: node.title,
          ),
        ),
      );
      if (mounted) widget.controller.refreshFeed();
      return;
    }
    if (node.type == NodeType.fileTree) {
      if (ws == null) return;
      final tree = node.rawData['fileTree'];
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FileTreeScreen(
            client: widget.controller.client,
            workspaceId: ws.id,
            nodeId: node.id,
            title: node.title,
            initiallyShowHidden: tree is Map && tree['showsHiddenFiles'] == true,
          ),
        ),
      );
      return;
    }
    if (node.type == NodeType.note) {
      if (ws == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NoteScreen(
            client: widget.controller.client,
            workspaceId: ws.id,
            nodeId: node.id,
            title: node.title,
          ),
        ),
      );
      if (mounted) widget.controller.refreshFeed();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalFullscreen(
          node: node,
          controller: widget.controller,
        ),
      ),
    );
    if (mounted) {
      widget.controller.refreshFeed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (widget.controller.status != ConnectionStatus.connected) {
          return PairScreen(
            controller: widget.controller,
            onPairedSuccess: () {
              setState(() {});
            },
          );
        }

        final canvas = _canvas ?? const CanvasSnapshot();

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          drawer: WorkspaceSidebar(
            workspaces: widget.controller.workspaces,
            activeWorkspace: widget.controller.activeWorkspace,
            onSelectWorkspace: (ws) => widget.controller.selectWorkspace(ws),
            onAddWorkspace: () {},
            onOpenRoutines: _openRoutines,
            onOpenRoles: _openRoles,
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Barra de Janela Superior Estilo Mac
                MacWindowBar(
                  hostName: widget.controller.hostName,
                  isConnected:
                      widget.controller.status == ConnectionStatus.connected,
                  activeWorkspace: widget.controller.activeWorkspace,
                  onOpenSidebar: () => _scaffoldKey.currentState?.openDrawer(),
                  onNewPrompt: _openPromptComposer,
                ),

                // Canvas Infinito 2D com nós e cabos
                Expanded(
                  child: Stack(
                    children: [
                      InfiniteCanvas(
                        nodes: canvas.nodes,
                        client: widget.controller.client,
                        onCreateNote: _createNote,
                        onCreateText: _canWrite ? _createText : null,
                        onOpenFloors: _openFloors,
                        onCreateTerminal: _createTerminal,
                        onNodeMoved: _moveNode,
                        onNodeResized: _moveNode,
                        onNodeOpen: _openTerminalFullscreen,
                        onNodeSelectTap: _toggleSelect,
                        onNodeLongPress: _showNodeActions,
                        onConnect: _canWrite ? _connectNodes : null,
                        onCableTap: _canWrite ? _onCableTap : null,
                        onBackgroundTap: () => setState(() => _selected.clear()),
                        cablesFromEndpoints: widget.controller.ropeRouting == 'circuit',
                        cables: canvas.connections,
                        groups: canvas.groups,
                        drawings: canvas.drawings,
                        ties: canvas.ties,
                        selectedIds: _selected,
                        selectMode: _selectMode,
                        canEdit: _canWrite,
                      ),
                      if (_canWrite)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: FloatingActionButton.small(
                            heroTag: 'selecionar',
                            tooltip: _selectMode ? 'Sair da seleção' : 'Selecionar nós',
                            backgroundColor: _selectMode
                                ? AppColors.neonViolet
                                : AppColors.surfaceElevated,
                            foregroundColor: AppColors.neonViolet,
                            onPressed: () => _selectMode ? _exitSelectMode() : setState(() => _selectMode = true),
                            child: Icon(_selectMode ? Icons.close_rounded : Icons.checklist_rounded),
                          ),
                        ),
                      if (_selectMode || _selected.isNotEmpty) _selectionBar(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
