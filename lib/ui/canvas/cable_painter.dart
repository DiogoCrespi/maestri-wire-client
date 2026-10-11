import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/canvas_node.dart';
import '../../models/cable_tie.dart';

/// Desenha cabos de conexão curvos (Bezier Cúbicos) entre os nós no canvas,
/// com pulsos de luz animados indicando tráfego de dados ativo entre os agentes.
class CablePainter extends CustomPainter {
  final List<CanvasNode> nodes;
  final List<CableTie> cables;
  final double animationValue; // 0.0 a 1.0 para animar pulsos de energia

  CablePainter({
    required this.nodes,
    required this.cables,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty || cables.isEmpty) return;

    final nodeMap = {for (var n in nodes) n.id: n};

    final basePaint = Paint()
      ..color = AppColors.cableBase
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final activePaint = Paint()
      ..color = AppColors.cableActive
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = AppColors.cableGlow
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    final pulsePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (var cable in cables) {
      final fromNode = nodeMap[cable.fromNodeId];
      final toNode = nodeMap[cable.toNodeId];
      if (fromNode == null || toNode == null) continue;

      // Ponto de saída do lado direito do primeiro nó
      final start = Offset(
        fromNode.position.dx + fromNode.size.width,
        fromNode.position.dy + fromNode.size.height / 2,
      );

      // Ponto de entrada do lado esquerdo do segundo nó
      final end = Offset(
        toNode.position.dx,
        toNode.position.dy + toNode.size.height / 2,
      );

      // Pontos de controle da curva de Bézier (suave e curvada)
      final dx = (end.dx - start.dx).abs() * 0.5;
      final controlPoint1 = Offset(start.dx + dx, start.dy);
      final controlPoint2 = Offset(end.dx - dx, end.dy);

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          controlPoint1.dx,
          controlPoint1.dy,
          controlPoint2.dx,
          controlPoint2.dy,
          end.dx,
          end.dy,
        );

      if (cable.isFlowing) {
        // Cabo ativo com brilho neon
        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, activePaint);

        // Pulso de energia viajando pelo cabo
        for (final metric in path.computeMetrics()) {
          final distance = metric.length * ((animationValue) % 1.0);
          final tangent = metric.getTangentForOffset(distance);
          if (tangent != null) {
            canvas.drawCircle(tangent.position, 3.5, pulsePaint);
            canvas.drawCircle(
              tangent.position,
              6.0,
              Paint()
                ..color = AppColors.neonViolet.withOpacity(0.6)
                ..style = PaintingStyle.fill,
            );
          }
        }
      } else {
        // Cabo inativo elegante
        canvas.drawPath(path, basePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CablePainter oldDelegate) => true;
}
