import 'package:flutter/material.dart';

/// Corda (Connection) do canvas. `kind` é um de terminal, note, noteToNote, portal,
/// portalToPortal, crossFloor, crossWorkspace (tipos desconhecidos viram "outro").
class CableTie {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final String kind;
  final String? label;
  final Color? color;
  final bool isFlowing;

  /// Caminho roteado pelo host, em coordenadas do canvas (mesmo sistema dos nós).
  /// Vazio quando o host não envia pontos; nesse caso o cabo é desenhado entre os nós.
  final List<Offset> points;

  CableTie({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    this.kind = 'terminal',
    this.label,
    this.color,
    this.isFlowing = false,
    this.points = const [],
  });

  factory CableTie.fromJson(Map<String, dynamic> json) {
    return CableTie(
      id: (json['id'] ?? '').toString(),
      fromNodeId: (json['from'] ?? json['fromNodeId'] ?? '').toString(),
      toNodeId: (json['to'] ?? json['toNodeId'] ?? '').toString(),
      kind: (json['kind'] ?? 'terminal').toString(),
      label: json['label'] as String?,
      isFlowing: json['flowing'] == true || json['isFlowing'] == true || json['isActive'] == true,
      points: _parsePoints(json['points']),
    );
  }

  static List<Offset> _parsePoints(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final p in raw)
        if (p is Map && p['x'] is num && p['y'] is num)
          Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
    ];
  }
}
