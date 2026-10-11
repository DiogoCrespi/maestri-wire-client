import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/mac_theme.dart';
import '../../models/canvas_node.dart';
import '../../state/wire_controller.dart';
import '../canvas/infinite_canvas.dart';
import '../widgets/mac_window_bar.dart';
import '../widgets/workspace_sidebar.dart';
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

  void _openTerminalFullscreen(CanvasNode node) async {
    if (node.type == NodeType.portal) {
      _showPortalModal(node);
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

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          drawer: WorkspaceSidebar(
            workspaces: widget.controller.workspaces,
            activeWorkspace: widget.controller.activeWorkspace,
            onSelectWorkspace: (ws) => widget.controller.selectWorkspace(ws),
            onAddWorkspace: () {},
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
                  child: InfiniteCanvas(
                    nodes: widget.controller.nodes,
                    cables: widget.controller.cables,
                    onTerminalOpen: _openTerminalFullscreen,
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
