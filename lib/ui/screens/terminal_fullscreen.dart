import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/terminal_stream.dart';
import '../../models/canvas_node.dart';
import '../../state/wire_controller.dart';

/// Tela cheia de Terminal Interativo com streaming PTY e barra de atalhos rápidos
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
  final ScrollController _scrollController = ScrollController();
  final List<String> _outputLines = [];

  bool get _isAgent =>
      widget.node.title.toLowerCase().contains('codex') ||
      widget.node.title.toLowerCase().contains('claude') ||
      (widget.node.rawData['terminal']?['agentType'] != null &&
          widget.node.rawData['terminal']?['agentType'] != 'generic_shell');

  @override
  void initState() {
    super.initState();

    // Carrega o histórico recente do nó para visualização imediata
    final preview = widget.node.previewText;
    if (preview != null && preview.isNotEmpty) {
      final lines = preview.split('\n');
      _outputLines.addAll(lines);
    }

    _stream = TerminalStream(
      client: widget.controller.client,
      terminalId: widget.node.terminalId ?? widget.node.id,
    );

    _stream.output.listen((data) {
      if (mounted) {
        setState(() {
          final lines = data.split(RegExp(r'\r?\n'));
          for (final rawLine in lines) {
            final line = rawLine.trimRight();
            if (line.isEmpty) continue;

            // Evita duplicar exatamente a mesma linha consecutiva (ex: redraw de terminal)
            if (_outputLines.isNotEmpty && _outputLines.last == line) {
              continue;
            }

            // Se for atualização de linha de status como "Worked for ...", substitui a anterior
            if (line.startsWith('Worked for ') &&
                _outputLines.isNotEmpty &&
                _outputLines.last.startsWith('Worked for ')) {
              _outputLines.last = line;
              continue;
            }

            _outputLines.add(line);
          }
        });
        _scrollToBottom();
      }
    });

    _stream.connect();
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

  void _sendCurrentInput() {
    final text = _inputController.text.trim();
    if (text.isNotEmpty) {
      final terminalId = widget.node.terminalId ?? widget.node.id;
      // Para agentes (Codex, Claude), despacha via endpoint de Prompt em UTF-8 limpo
      if (_isAgent) {
        widget.controller.client.sendPrompt(
          terminalId: terminalId,
          prompt: text,
        );
        setState(() {
          _outputLines.add('› $text');
        });
      } else {
        // Para Shell genérico, envia bytes brutos UTF-8 ao PTY
        _stream.sendInput('$text\n');
      }
      _inputController.clear();
      _scrollToBottom();
    }
  }

  void _approveAction() async {
    final terminalId = widget.node.terminalId ?? widget.node.id;
    await widget.controller.client.approveTerminal(terminalId);
    _stream.sendInput('y\n');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ação aprovada com sucesso!'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _rejectAction() async {
    final terminalId = widget.node.terminalId ?? widget.node.id;
    await widget.controller.client.rejectTerminal(terminalId);
    _stream.sendInput('n\n');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ação rejeitada.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _copyAllOutput() {
    if (_outputLines.isNotEmpty) {
      final allText = _outputLines.join('\n');
      Clipboard.setData(ClipboardData(text: allText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todo o histórico do terminal foi copiado!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _stream.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          IconButton(
            icon: const Icon(Icons.copy_all_rounded, size: 20),
            tooltip: 'Copiar Tudo',
            onPressed: _copyAllOutput,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, size: 20),
            tooltip: 'Limpar Tela',
            onPressed: () => setState(() => _outputLines.clear()),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Área de Texto do Terminal (PTY Stream) com Seleção e Cópia estável
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    _outputLines.join('\n'),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
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
                  _shortcutButton('Ctrl+C', () => _stream.sendInput('\x03')),
                  _shortcutButton('Tab', () => _stream.sendInput('\t')),
                  _shortcutButton('Esc', () => _stream.sendInput('\x1b')),
                  _shortcutButton('Enter', () => _stream.sendInput('\n')),
                  _shortcutButton('▲ Up', () => _stream.sendInput('\x1b[A')),
                  _shortcutButton('▼ Down', () => _stream.sendInput('\x1b[B')),
                ],
              ),
            ),

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
                  const Text('❯ ',
                      style: TextStyle(
                          color: AppColors.statusActive,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Digite um comando ou prompt...',
                        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendCurrentInput(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    color: AppColors.neonViolet,
                    onPressed: _sendCurrentInput,
                  ),
                ],
              ),
            ),
          ],
        ),
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
