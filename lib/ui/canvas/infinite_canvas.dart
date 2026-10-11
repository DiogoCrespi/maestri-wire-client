import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/canvas_node.dart';
import '../../models/cable_tie.dart';
import 'cable_painter.dart';
import 'terminal_node_widget.dart';
import 'portal_node_widget.dart';
import 'node_card.dart';

/// Canvas Infinito 2D com pan, zoom, grid de pontos e renderização de cabos e nós.
class InfiniteCanvas extends StatefulWidget {
  final List<CanvasNode> nodes;
  final List<CableTie> cables;
  final Function(CanvasNode)? onNodeSelected;
  final Function(CanvasNode)? onTerminalOpen;

  const InfiniteCanvas({
    Key? key,
    required this.nodes,
    required this.cables,
    this.onNodeSelected,
    this.onTerminalOpen,
  }) : super(key: key);

  @override
  State<InfiniteCanvas> createState() => _InfiniteCanvasState();
}

class _InfiniteCanvasState extends State<InfiniteCanvas>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late AnimationController _pulseController;
  String? _selectedNodeId;
  bool _hasCentered = false;

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

  @override
  void dispose() {
    _pulseController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  // Camada 1: Cabos e Conexões Bézier animadas
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: CablePainter(
                            nodes: widget.nodes,
                            cables: widget.cables,
                            animationValue: _pulseController.value,
                          ),
                        );
                      },
                    ),
                  ),

                  // Camada 2: Cards de Nós flutuantes
                  for (final node in widget.nodes)
                    Positioned(
                      left: node.position.dx,
                      top: node.position.dy,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedNodeId = node.id);
                          widget.onNodeSelected?.call(node);
                          if (node.type == NodeType.terminal ||
                              node.type == NodeType.portal) {
                            widget.onTerminalOpen?.call(node);
                          }
                        },
                        child: node.type == NodeType.terminal
                            ? TerminalNodeWidget(
                                node: node,
                                isSelected: _selectedNodeId == node.id,
                                onOpenFullscreen: () =>
                                    widget.onTerminalOpen?.call(node),
                              )
                            : node.type == NodeType.portal
                                ? PortalNodeWidget(
                                    node: node,
                                    isSelected: _selectedNodeId == node.id,
                                    onTap: () => widget.onTerminalOpen?.call(node),
                                  )
                                : NodeCard(
                                    node: node,
                                    isSelected: _selectedNodeId == node.id,
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(
                                        node.previewText ?? 'Nó de dados ativo',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                      ),
                    ),
                ],
              ),
            ),
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
