import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/canvas/cable_tie_group.dart';
import '../../models/canvas/canvas_group.dart';
import '../../models/canvas/connection.dart';
import '../../models/canvas/drawing.dart';
import '../../models/canvas_node.dart';
import '../../core/network/wire_client.dart';
import 'cable_painter.dart';
import 'canvas_node_widgets/canvas_node_body.dart';
import 'terminal_node_widget.dart';
import 'portal_node_widget.dart';

/// Canvas Infinito 2D com pan, zoom, grid de pontos, cabos, grupos, desenhos e nós.
/// Não guarda seleção: quem usa passa [selectedIds] e recebe os toques.
class InfiniteCanvas extends StatefulWidget {
  final List<CanvasNode> nodes;
  final WireClient? client;
  final bool cablesFromEndpoints;
  final List<Connection> cables;
  final List<CanvasGroup> groups;
  final List<Drawing> drawings;
  final List<CableTieGroup> ties;
  /// Ids dos nós selecionados (seleção múltipla).
  final Set<String> selectedIds;
  /// Com a seleção ligada, um toque alterna a seleção em vez de abrir o nó.
  final bool selectMode;
  /// Owner com `canvasWrites`: permite mover, redimensionar e criar cordas.
  final bool canEdit;

  final VoidCallback? onCreateNote;
  final VoidCallback? onCreateText;
  final VoidCallback? onOpenFloors;
  final VoidCallback? onCreateTerminal;
  /// Nó arrastado e solto: salvar a posição no host
  final ValueChanged<CanvasNode>? onNodeMoved;
  /// Alça de redimensionar solta: salvar o frame no host
  final ValueChanged<CanvasNode>? onNodeResized;
  /// Toque com a seleção desligada: abrir o nó
  final ValueChanged<CanvasNode>? onNodeOpen;
  /// Toque com a seleção ligada
  final ValueChanged<CanvasNode>? onNodeSelectTap;
  /// Toque longo num nó: ações do nó
  final ValueChanged<CanvasNode>? onNodeLongPress;
  /// Porta de um nó arrastada até outro nó
  final void Function(CanvasNode from, CanvasNode to)? onConnect;
  /// Toque num cabo
  final ValueChanged<Connection>? onCableTap;
  /// Toque no fundo do canvas (limpa a seleção)
  final VoidCallback? onBackgroundTap;

  const InfiniteCanvas({
    Key? key,
    required this.nodes,
    this.client,
    this.cablesFromEndpoints = false,
    required this.cables,
    this.groups = const [],
    this.drawings = const [],
    this.ties = const [],
    this.selectedIds = const {},
    this.selectMode = false,
    this.canEdit = false,
    this.onCreateNote,
    this.onCreateText,
    this.onOpenFloors,
    this.onCreateTerminal,
    this.onNodeMoved,
    this.onNodeResized,
    this.onNodeOpen,
    this.onNodeSelectTap,
    this.onNodeLongPress,
    this.onConnect,
    this.onCableTap,
    this.onBackgroundTap,
  }) : super(key: key);

  @override
  State<InfiniteCanvas> createState() => _InfiniteCanvasState();
}

class _InfiniteCanvasState extends State<InfiniteCanvas>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late AnimationController _pulseController;
  bool _hasCentered = false;

  /// Corda em criação: de onde sai e onde está o dedo (coordenadas do canvas).
  Offset? _ropeFrom;
  Offset? _ropeTo;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.nodes.isNotEmpty) {
        _centerOnNodes();
      }
    });
  }

  @override
  void didUpdateWidget(covariant InfiniteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasCentered && widget.nodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerOnNodes();
      });
    }
  }

  void _centerOnNodes() {
    if (widget.nodes.isEmpty || !mounted) return;

    double minX = widget.nodes.first.position.dx;
    double maxX = widget.nodes.first.position.dx + widget.nodes.first.size.width;
    double minY = widget.nodes.first.position.dy;
    double maxY = widget.nodes.first.position.dy + widget.nodes.first.size.height;

    for (final node in widget.nodes) {
      if (node.position.dx < minX) minX = node.position.dx;
      if (node.position.dx + node.size.width > maxX) {
        maxX = node.position.dx + node.size.width;
      }
      if (node.position.dy < minY) minY = node.position.dy;
      if (node.position.dy + node.size.height > maxY) {
        maxY = node.position.dy + node.size.height;
      }
    }

    final double centerX = (minX + maxX) / 2;
    final double centerY = (minY + maxY) / 2;

    final renderBox = context.findRenderObject() as RenderBox?;
    final viewportWidth = renderBox?.size.width ?? 400.0;
    final viewportHeight = renderBox?.size.height ?? 800.0;

    const double targetScale = 0.35;
    final double tx = -centerX * targetScale + (viewportWidth / 2);
    final double ty = -centerY * targetScale + (viewportHeight / 2);

    _transformationController.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(targetScale);
    _hasCentered = true;
  }

  double get _scale => _transformationController.value.getMaxScaleOnAxis();

  /// Nó que aceita corda sob o ponto (exceto [exceptId]), o de maior zIndex.
  CanvasNode? _connectableAt(Offset point, String exceptId) {
    CanvasNode? best;
    for (final n in widget.nodes) {
      if (n.id == exceptId || !n.isConnectable) continue;
      if (!n.rect.inflate(12).contains(point)) continue;
      if (best == null || n.zIndex >= best.zIndex) best = n;
    }
    return best;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodeMap = {for (final n in widget.nodes) n.id: n};
    final sortedNodes = [...widget.nodes]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return Stack(
      children: [
        // Grid de Fundo com Dots estilo Mac
        Positioned.fill(
          child: CustomPaint(
            painter: _CanvasGridPainter(
              controller: _transformationController,
            ),
          ),
        ),

        // InteractiveViewer com suporte a gestos de pinça (zoom) e arrasto (pan)
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _transformationController,
            boundaryMargin: const EdgeInsets.all(25000),
            minScale: 0.1,
            maxScale: 3.0,
            constrained: false,
            child: SizedBox(
              width: 25000,
              height: 25000,
              child: Stack(
                children: [
                  // Camada 0: caixas dos grupos, atrás de tudo
                  if (widget.groups.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: CanvasGroupsPainter(nodes: widget.nodes, groups: widget.groups),
                        ),
                      ),
                    ),

                  // Camada 1: Cabos (toque no cabo desconecta; toque no fundo limpa a seleção)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (d) {
                        final cable = hitTestCable(
                          d.localPosition,
                          widget.cables,
                          nodeMap,
                          fromEndpoints: widget.cablesFromEndpoints,
                        );
                        if (cable != null) {
                          widget.onCableTap?.call(cable);
                        } else {
                          widget.onBackgroundTap?.call();
                        }
                      },
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: CablePainter(
                              nodes: widget.nodes,
                              cables: widget.cables,
                              animationValue: _pulseController.value,
                              fromEndpoints: widget.cablesFromEndpoints,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Camada 2: desenhos (somente leitura) e abraçadeiras
                  if (widget.drawings.isNotEmpty || widget.ties.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: CanvasOverlayPainter(drawings: widget.drawings, ties: widget.ties),
                        ),
                      ),
                    ),

                  // Camada 3: Cards de Nós flutuantes
                  for (final node in sortedNodes) _buildNode(node),

                  // Camada 4: portas e alças (ficam fora do corpo do nó para não brigar com o arrasto)
                  for (final node in sortedNodes) ..._buildHandles(node),

                  // Camada 5: corda em criação
                  if (_ropeFrom != null && _ropeTo != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: DraftRopePainter(from: _ropeFrom!, to: _ropeTo!),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Novo terminal (Claude, Codex, Antigravity, OpenCode, Shell)
        if (widget.onCreateTerminal != null)
          Positioned(
            left: 16,
            bottom: 124,
            child: FloatingActionButton.small(
              heroTag: 'novoTerminal',
              tooltip: 'Novo terminal',
              backgroundColor: AppColors.surfaceElevated,
              foregroundColor: AppColors.neonViolet,
              onPressed: widget.onCreateTerminal,
              child: const Icon(Icons.add_box_rounded),
            ),
          ),

        // Novo bloco de texto
        if (widget.onCreateText != null)
          Positioned(
            left: 16,
            bottom: 180,
            child: FloatingActionButton.small(
              heroTag: 'novoTexto',
              tooltip: 'Novo texto',
              backgroundColor: AppColors.surfaceElevated,
              foregroundColor: AppColors.neonViolet,
              onPressed: widget.onCreateText,
              child: const Icon(Icons.title_rounded),
            ),
          ),

        // Seletor de andares do workspace
        if (widget.onOpenFloors != null)
          Positioned(
            left: 16,
            bottom: 68,
            child: FloatingActionButton.small(
              heroTag: 'andares',
              tooltip: 'Andares',
              backgroundColor: AppColors.surfaceElevated,
              foregroundColor: AppColors.neonViolet,
              onPressed: widget.onOpenFloors,
              child: const Icon(Icons.layers_rounded),
            ),
          ),

        // Botão para criar uma nota no canvas do host
        if (widget.onCreateNote != null)
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'novaNota',
              tooltip: 'Nova nota',
              backgroundColor: AppColors.surfaceElevated,
              foregroundColor: AppColors.neonViolet,
              onPressed: widget.onCreateNote,
              child: const Icon(Icons.sticky_note_2_rounded),
            ),
          ),

        // Controles Flutuantes: Botão Centralizar e Minimapa no canto inferior direito
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'recenter_btn',
                backgroundColor: AppColors.surfaceElevated.withOpacity(0.9),
                foregroundColor: AppColors.neonViolet,
                elevation: 4,
                onPressed: _centerOnNodes,
                child: const Icon(Icons.filter_center_focus_rounded, size: 20),
              ),
              const SizedBox(height: 8),
              _buildMiniMap(),
            ],
          ),
        ),
      ],
    );
  }

  /// Corpo do nó com toque, toque longo e arrasto (só se o nó não estiver travado).
  Widget _buildNode(CanvasNode node) {
    final selected = widget.selectedIds.contains(node.id);
    final movable = widget.canEdit && !node.isLocked;
    final Widget body;
    switch (node.type) {
      case NodeType.terminal:
        body = TerminalNodeWidget(
          node: node,
          isSelected: selected,
          onOpenFullscreen: () => widget.onNodeOpen?.call(node),
        );
      case NodeType.portal:
        body = PortalNodeWidget(
          node: node,
          isSelected: selected,
          onTap: () => widget.onNodeOpen?.call(node),
          client: widget.client,
        );
      default:
        body = buildCanvasNodeBody(node, isSelected: selected);
    }

    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: GestureDetector(
        onPanUpdate: movable
            ? (d) => setState(() => node.position = node.position + d.delta / _scale)
            : null,
        onPanEnd: movable ? (_) => widget.onNodeMoved?.call(node) : null,
        onTap: () {
          if (widget.selectMode) {
            widget.onNodeSelectTap?.call(node);
          } else {
            widget.onNodeOpen?.call(node);
          }
        },
        onLongPress: widget.onNodeLongPress == null ? null : () => widget.onNodeLongPress!(node),
        child: body,
      ),
    );
  }

  /// Porta de corda (lado direito, para nós que aceitam corda) e alça de redimensionar (nó selecionado).
  List<Widget> _buildHandles(CanvasNode node) {
    if (!widget.canEdit) return const [];
    final handles = <Widget>[];

    if (node.isConnectable && !widget.selectMode) {
      final port = node.position + Offset(node.size.width, node.size.height / 2);
      handles.add(Positioned(
        left: port.dx - 11,
        top: port.dy - 11,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => setState(() {
            _ropeFrom = port;
            _ropeTo = port;
          }),
          onPanUpdate: (d) => setState(() => _ropeTo = _ropeTo! + d.delta / _scale),
          onPanEnd: (_) {
            final target = _ropeTo == null ? null : _connectableAt(_ropeTo!, node.id);
            setState(() {
              _ropeFrom = null;
              _ropeTo = null;
            });
            if (target != null) widget.onConnect?.call(node, target);
          },
          onPanCancel: () => setState(() {
            _ropeFrom = null;
            _ropeTo = null;
          }),
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonViolet,
                border: Border.all(color: AppColors.background, width: 1.5),
              ),
            ),
          ),
        ),
      ));
    }

    final resizable = node.type != NodeType.text && node.type != NodeType.connector;
    if (widget.selectedIds.contains(node.id) && resizable && !node.isLocked) {
      final corner = node.position + Offset(node.size.width, node.size.height);
      handles.add(Positioned(
        left: corner.dx - 12,
        top: corner.dy - 12,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => setState(() {
            final delta = d.delta / _scale;
            node.size = Size(
              max(120.0, node.size.width + delta.dx),
              max(80.0, node.size.height + delta.dy),
            );
          }),
          onPanEnd: (_) => widget.onNodeResized?.call(node),
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                border: Border.all(color: AppColors.neonViolet, width: 1.5),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ));
    }
    return handles;
  }

  Widget _buildMiniMap() {
    return Container(
      width: 120,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _MiniMapPainter(nodes: widget.nodes),
        ),
      ),
    );
  }
}

/// Renderiza a grade pontilhada (dots) do Canvas Infinito
class _CanvasGridPainter extends CustomPainter {
  final TransformationController controller;

  _CanvasGridPainter({required this.controller}) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final matrix = controller.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();

    const double baseSpacing = 28.0;
    final double spacing = baseSpacing * scale;
    if (spacing < 10) return; // Evita excesso de densidade em muito zoom out

    final double startX = translation.x % spacing;
    final double startY = translation.y % spacing;

    final paint = Paint()
      ..color = AppColors.canvasGridDots.withOpacity(min(1.0, scale * 0.9))
      ..style = PaintingStyle.fill;

    for (double x = startX; x < size.width; x += spacing) {
      for (double y = startY; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2 * min(scale, 1.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasGridPainter oldDelegate) => true;
}

/// Renderiza a visão aérea em miniatura (Minimap)
class _MiniMapPainter extends CustomPainter {
  final List<CanvasNode> nodes;

  _MiniMapPainter({required this.nodes});

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final paint = Paint()..color = AppColors.neonViolet.withOpacity(0.85);

    double minX = nodes.first.position.dx;
    double maxX = nodes.first.position.dx + nodes.first.size.width;
    double minY = nodes.first.position.dy;
    double maxY = nodes.first.position.dy + nodes.first.size.height;

    for (final node in nodes) {
      if (node.position.dx < minX) minX = node.position.dx;
      if (node.position.dx + node.size.width > maxX) maxX = node.position.dx + node.size.width;
      if (node.position.dy < minY) minY = node.position.dy;
      if (node.position.dy + node.size.height > maxY) maxY = node.position.dy + node.size.height;
    }

    final double rangeX = max(200.0, (maxX - minX) * 1.2);
    final double rangeY = max(200.0, (maxY - minY) * 1.2);
    final double originX = minX - (rangeX - (maxX - minX)) / 2;
    final double originY = minY - (rangeY - (maxY - minY)) / 2;

    for (final node in nodes) {
      final dx = ((node.position.dx - originX) / rangeX) * size.width;
      final dy = ((node.position.dy - originY) / rangeY) * size.height;
      final w = max(5.0, (node.size.width / rangeX) * size.width);
      final h = max(4.0, (node.size.height / rangeY) * size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(dx, dy, w, h), const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}
