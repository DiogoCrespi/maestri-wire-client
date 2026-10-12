import 'dart:ui' show Offset, Size;

import 'json_values.dart';

/// Ponta de uma corda presa a um desenho (`sourceConnection` / `targetConnection`).
class DrawingConnectionRef {
  final String drawingId;

  /// `top`, `bottom`, `left` ou `right`.
  final String edge;

  const DrawingConnectionRef({required this.drawingId, required this.edge});

  static DrawingConnectionRef? fromJson(Object? raw) {
    final m = readMap(raw);
    if (m == null) return null;
    final id = readString(m['drawingId']);
    if (id == null || id.isEmpty) return null;
    return DrawingConnectionRef(
      drawingId: id,
      edge: readStringOr(m['edge'], ''),
    );
  }
}

/// `DrawingPath` guardado pelo host (`drawings` do snapshot).
///
/// [points] são locais a [origin] e escalam por `size / originalSize`; use
/// [canvasPoints] para obter pontos já no sistema do canvas.
class Drawing {
  final String id;

  /// `pen`, `brush`, `smartDraw`, `arrow`, `rectangle`, `blockArrowRight`, ... (texto cru do host).
  final String tool;
  final List<Offset> points;
  final Offset origin;
  final Size originalSize;
  final Size size;

  /// Cor em hex, do jeito que o host manda.
  final String color;
  final double lineWidth;
  final double opacity;
  final int zIndex;
  final bool isLocked;
  final double rotation;
  final String? textContent;
  final double textFontSize;
  final DrawingConnectionRef? sourceConnection;
  final DrawingConnectionRef? targetConnection;

  /// `solid`, `dashed` ou `dotted`.
  final String? strokePattern;

  /// `noFill`, `hachure`, `crossHatch`, `tint` ou `solidOpaque`.
  final String? fillStyle;
  final double? cornerRadius;
  final Offset? controlPointOffset;
  final String? groupId;

  const Drawing({
    required this.id,
    this.tool = 'pen',
    this.points = const [],
    this.origin = Offset.zero,
    this.originalSize = Size.zero,
    this.size = Size.zero,
    this.color = '#000000',
    this.lineWidth = 2,
    this.opacity = 1,
    this.zIndex = 0,
    this.isLocked = false,
    this.rotation = 0,
    this.textContent,
    this.textFontSize = 14,
    this.sourceConnection,
    this.targetConnection,
    this.strokePattern,
    this.fillStyle,
    this.cornerRadius,
    this.controlPointOffset,
    this.groupId,
  });

  /// Fator de escala dos pontos (`size / originalSize`); 1 quando não há tamanho original.
  Size get scale {
    final ow = originalSize.width;
    final oh = originalSize.height;
    final sw = ow > 0 ? size.width / ow : 1.0;
    final sh = oh > 0 ? size.height / oh : 1.0;
    return Size(sw, sh);
  }

  /// Pontos já no sistema do canvas: `origin + p * scale`.
  List<Offset> get canvasPoints {
    final s = scale;
    return [
      for (final p in points)
        Offset(origin.dx + p.dx * s.width, origin.dy + p.dy * s.height),
    ];
  }

  factory Drawing.fromJson(Map<String, dynamic> json) {
    final size = readSize(json['size']) ?? Size.zero;
    final originalSize = readSize(json['originalSize']) ?? size;
    final cro = readOffset(json['controlPointOffset']);
    return Drawing(
      id: readStringOr(json['id'], ''),
      tool: readStringOr(json['tool'], 'pen'),
      points: readOffsets(json['points']),
      origin: readOffset(json['origin']) ?? Offset.zero,
      originalSize: originalSize,
      size: size,
      color: readStringOr(json['color'], '#000000'),
      lineWidth: readDoubleOr(json['lineWidth'], 2),
      opacity: readDoubleOr(json['opacity'], 1),
      zIndex: readIntOr(json['zIndex'], 0),
      isLocked: readBoolOr(json['isLocked'], false),
      rotation: readDoubleOr(json['rotation'], 0),
      textContent: readString(json['textContent']),
      textFontSize: readDoubleOr(json['textFontSize'], 14),
      sourceConnection: DrawingConnectionRef.fromJson(json['sourceConnection']),
      targetConnection: DrawingConnectionRef.fromJson(json['targetConnection']),
      strokePattern: readString(json['strokePattern']),
      fillStyle: readString(json['fillStyle']),
      cornerRadius: readDouble(json['cornerRadius']),
      controlPointOffset: cro,
      groupId: readString(json['groupId']),
    );
  }

  /// Descarta entradas sem id.
  static List<Drawing> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (readMap(e) case final m?) Drawing.fromJson(m),
    ].where((d) => d.id.isNotEmpty).toList();
  }
}
