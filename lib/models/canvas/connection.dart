import 'dart:ui' show Offset;

import 'connection_kind.dart';
import 'json_values.dart';

/// Uma corda do contrato (`Connection`).
///
/// Quando `ropeRouting` é `circuit`, [points] pode estar desatualizado: desenhe
/// a partir das pontas (veja `routeEndpoints` em route.dart).
class Connection {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final ConnectionKind kind;
  final bool isActive;
  final List<Offset> points;

  /// Quando a ponta é um fichário, o nó da página real.
  final String? fromNoteNodeId;
  final String? toNoteNodeId;

  const Connection({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.kind,
    this.isActive = false,
    this.points = const [],
    this.fromNoteNodeId,
    this.toNoteNodeId,
  });

  factory Connection.fromJson(Map<String, dynamic> json) {
    return Connection(
      id: readStringOr(json['id'], ''),
      fromNodeId: readStringOr(json['fromNodeId'], ''),
      toNodeId: readStringOr(json['toNodeId'], ''),
      kind: ConnectionKind.parse(json['kind']),
      isActive: readBoolOr(json['isActive'], false),
      points: readOffsets(json['points']),
      fromNoteNodeId: readString(json['fromNoteNodeId']),
      toNoteNodeId: readString(json['toNoteNodeId']),
    );
  }

  /// Descarta entradas que não são objeto ou que não têm id e pontas.
  static List<Connection> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (readMap(e) case final m?) Connection.fromJson(m),
    ].where((c) => c.id.isNotEmpty && c.fromNodeId.isNotEmpty && c.toNodeId.isNotEmpty).toList();
  }
}
