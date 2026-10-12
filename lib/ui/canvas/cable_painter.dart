import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/canvas/cable_tie_group.dart';
import '../../models/canvas/canvas_group.dart';
import '../../models/canvas/connection.dart';
import '../../models/canvas/connection_kind.dart';
import '../../models/canvas/drawing.dart';
import '../../models/canvas/route.dart';
import '../../models/canvas_node.dart';

/// Estilo de um cabo conforme o `kind` da conexão.
class CableStyle {
  final Color color;
  final bool dashed;
  final double width;

  const CableStyle(this.color, {this.dashed = false, this.width = 2});
}

/// Cor e traço por kind: terminal (violeta), nota (azul-céu), portal (âmbar),
/// crossFloor (lilás tracejado) e crossWorkspace (rosa tracejado). Desconhecido: cinza.
CableStyle cableStyleFor(ConnectionKind kind) {
  switch (kind) {
    case ConnectionKind.terminal:
      return const CableStyle(AppColors.cableBase);
    case ConnectionKind.note:
    case ConnectionKind.noteToNote:
      return const CableStyle(Color(0xFF38BDF8));
    case ConnectionKind.portal:
    case ConnectionKind.portalToPortal:
      return const CableStyle(Color(0xFFF59E0B));
    case ConnectionKind.crossFloor:
      return const CableStyle(Color(0xFFA78BFA), dashed: true);
    case ConnectionKind.crossWorkspace:
      return const CableStyle(Color(0xFFEC4899), dashed: true);
    case ConnectionKind.desconhecido:
      return const CableStyle(AppColors.textMuted);
  }
}

/// Caminho de uma corda em coordenadas do canvas. Em `fromEndpoints` (ropeRouting circuit)
/// ou sem pontos do host, desenha uma Bézier entre as pontas. Null se alguma ponta não está no andar.
Path? cablePath(Connection cable, Map<String, CanvasNode> nodeMap, {bool fromEndpoints = false}) {
  if (!fromEndpoints && cable.points.length >= 2) {
    final path = Path()..moveTo(cable.points.first.dx, cable.points.first.dy);
    for (final p in cable.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }
  final fromNode = nodeMap[cable.fromNodeId];
  final toNode = nodeMap[cable.toNodeId];
  if (fromNode == null || toNode == null) return null;
  if (fromEndpoints) {
    // Circuito: das pontas, na borda de cada nó na direção do outro
    final start = routeEndpoints(fromNode.rect, toNode.rect);
    final end = routeEndpoints(toNode.rect, fromNode.rect);
    final dx = ((end.dx - start.dx).abs() * 0.5).clamp(40.0, 400.0);
    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(start.dx + dx, start.dy, end.dx - dx, end.dy, end.dx, end.dy);
  }
  return CablePainter._bezierBetween(fromNode, toNode);
}

/// Cabo mais perto de [point] (até [tolerance] pontos), ou null. Usado para tocar um cabo.
Connection? hitTestCable(
  Offset point,
  List<Connection> cables,
  Map<String, CanvasNode> nodeMap, {
  bool fromEndpoints = false,
  double tolerance = 14,
}) {
  Connection? best;
  var bestDist = tolerance;
  for (final cable in cables) {
    final path = cablePath(cable, nodeMap, fromEndpoints: fromEndpoints);
    if (path == null) continue;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d <= metric.length; d += 6) {
        final pos = metric.getTangentForOffset(d)?.position;
        if (pos == null) continue;
        final dist = (pos - point).distance;
        if (dist < bestDist) {
          bestDist = dist;
          best = cable;
        }
      }
    }
  }
  return best;
}

/// Desenha cabos curvos (Bézier cúbica) entre os nós, com cor por kind e pulsos nos cabos ativos.
class CablePainter extends CustomPainter {
  final List<CanvasNode> nodes;
  final List<Connection> cables;
  final double animationValue; // 0.0 a 1.0 para animar pulsos de energia
  /// Ignora os pontos do host e desenha das pontas (modo `circuit`).
  final bool fromEndpoints;

  CablePainter({
    required this.nodes,
    required this.cables,
    required this.animationValue,
    this.fromEndpoints = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty || cables.isEmpty) return;

    final nodeMap = {for (var n in nodes) n.id: n};
    final pulsePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (final cable in cables) {
      final path = cablePath(cable, nodeMap, fromEndpoints: fromEndpoints);
      if (path == null) continue;
      final style = cableStyleFor(cable.kind);

      final basePaint = Paint()
        ..color = style.color
        ..strokeWidth = style.width
        ..style = PaintingStyle.stroke;

      if (cable.isActive) {
        // Cabo ativo com brilho neon
        final glowPaint = Paint()
          ..color = style.color.withValues(alpha: 0.4)
          ..strokeWidth = 6.0
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
        canvas.drawPath(path, glowPaint);
      }

      if (style.dashed) {
        _drawDashed(canvas, path, basePaint);
      } else {
        canvas.drawPath(path, basePaint);
      }

      if (cable.isActive) {
        // Pulso de energia viajando pelo cabo
        for (final metric in path.computeMetrics()) {
          final distance = metric.length * (animationValue % 1.0);
          final tangent = metric.getTangentForOffset(distance);
          if (tangent != null) {
            canvas.drawCircle(tangent.position, 3.5, pulsePaint);
            canvas.drawCircle(
              tangent.position,
              6.0,
              Paint()
                ..color = style.color.withValues(alpha: 0.6)
                ..style = PaintingStyle.fill,
            );
          }
        }
      }
    }
  }

  static void _drawDashed(Canvas canvas, Path path, Paint paint) {
    const dash = 8.0;
    const gap = 6.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  /// Fallback sem pontos do host: Bézier do lado mais próximo de cada nó.
  static Path _bezierBetween(CanvasNode fromNode, CanvasNode toNode) {
    final fromCenter = fromNode.position + Offset(fromNode.size.width / 2, fromNode.size.height / 2);
    final toCenter = toNode.position + Offset(toNode.size.width / 2, toNode.size.height / 2);
    final goingRight = toCenter.dx >= fromCenter.dx;
    final start = Offset(
      goingRight ? fromNode.position.dx + fromNode.size.width : fromNode.position.dx,
      fromCenter.dy,
    );
    final end = Offset(
      goingRight ? toNode.position.dx : toNode.position.dx + toNode.size.width,
      toCenter.dy,
    );
    final dx = (end.dx - start.dx).abs() * 0.5;
    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(start.dx + (goingRight ? dx : -dx), start.dy,
          end.dx - (goingRight ? dx : -dx), end.dy, end.dx, end.dy);
  }

  @override
  bool shouldRepaint(covariant CablePainter oldDelegate) => true;
}

/// Caixas de grupo atrás dos nós: envolvem os membros de cada grupo com um rótulo.
class CanvasGroupsPainter extends CustomPainter {
  final List<CanvasNode> nodes;
  final List<CanvasGroup> groups;

  CanvasGroupsPainter({required this.nodes, required this.groups});

  @override
  void paint(Canvas canvas, Size size) {
    for (final group in groups) {
      final members = nodes.where((n) => n.groupId == group.id).toList();
      if (members.isEmpty) continue;
      var box = members.first.rect;
      for (final n in members.skip(1)) {
        box = box.expandToInclude(n.rect);
      }
      box = box.inflate(20);
      final color = parseHexColor(group.colorHex) ?? AppColors.neonViolet;
      final rrect = RRect.fromRectAndRadius(box, const Radius.circular(18));
      canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.08));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      if (group.name.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: group.name,
            style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: box.width);
        tp.paint(canvas, box.topLeft + Offset(14, -tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CanvasGroupsPainter oldDelegate) => true;
}

/// Desenhos (somente leitura) e abraçadeiras do andar, por cima dos cabos.
class CanvasOverlayPainter extends CustomPainter {
  final List<Drawing> drawings;
  final List<CableTieGroup> ties;

  CanvasOverlayPainter({required this.drawings, required this.ties});

  static const _strokeTools = {'pen', 'brush', 'smartDraw', 'arrow', 'highlighter', 'line'};

  @override
  void paint(Canvas canvas, Size size) {
    final sorted = [...drawings]..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    for (final d in sorted) {
      final color = (parseHexColor(d.color) ?? AppColors.textPrimary).withValues(alpha: d.opacity.clamp(0.0, 1.0));
      final paint = Paint()
        ..color = color
        ..strokeWidth = d.lineWidth.clamp(1.0, 24.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final rect = Rect.fromLTWH(d.origin.dx, d.origin.dy, d.size.width, d.size.height);
      final pts = d.canvasPoints;

      if (d.tool == 'ellipse' || d.tool == 'oval') {
        canvas.drawOval(rect, paint);
      } else if (_strokeTools.contains(d.tool) && pts.length >= 2) {
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (final p in pts.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      } else if (d.tool == 'triangle' || d.tool == 'diamond' || d.tool == 'hexagon') {
        canvas.drawPath(_polygon(d.tool, rect), paint);
      } else {
        // Formas sem geometria própria aqui: o retângulo que elas ocupam.
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
      }
    }

    for (final tie in ties) {
      final band = Paint()
        ..color = AppColors.textMuted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: tie.position, width: 30, height: 12),
        const Radius.circular(6),
      );
      canvas.drawRRect(body, Paint()..color = AppColors.surfaceElevated);
      canvas.drawRRect(body, band);
    }
  }

  static Path _polygon(String tool, Rect r) {
    final path = Path();
    switch (tool) {
      case 'triangle':
        path
          ..moveTo(r.center.dx, r.top)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left, r.bottom);
      case 'diamond':
        path
          ..moveTo(r.center.dx, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.center.dx, r.bottom)
          ..lineTo(r.left, r.center.dy);
      default:
        path
          ..moveTo(r.left + r.width * 0.25, r.top)
          ..lineTo(r.left + r.width * 0.75, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.left + r.width * 0.75, r.bottom)
          ..lineTo(r.left + r.width * 0.25, r.bottom)
          ..lineTo(r.left, r.center.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant CanvasOverlayPainter oldDelegate) => true;
}

/// Corda em criação: arrastar da porta de um nó até outro.
class DraftRopePainter extends CustomPainter {
  final Offset from;
  final Offset to;

  DraftRopePainter({required this.from, required this.to});

  @override
  void paint(Canvas canvas, Size size) {
    final dx = ((to.dx - from.dx).abs() * 0.5).clamp(40.0, 400.0);
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(from.dx + dx, from.dy, to.dx - dx, to.dy, to.dx, to.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.neonViolet
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(to, 6, Paint()..color = AppColors.neonViolet);
  }

  @override
  bool shouldRepaint(covariant DraftRopePainter oldDelegate) =>
      oldDelegate.from != from || oldDelegate.to != to;
}
