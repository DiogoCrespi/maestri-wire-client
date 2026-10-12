import 'dart:ui' show Offset;

import 'json_values.dart';

/// Abraçadeira do andar (`cableTies` do snapshot). Une as cordas pelo
/// `Connection.id` na ordem da fita; o cliente prende [position] lado a lado.
class CableTieGroup {
  final String id;
  final Offset position;
  final List<String> memberConnectionIds;

  const CableTieGroup({
    required this.id,
    required this.position,
    this.memberConnectionIds = const [],
  });

  factory CableTieGroup.fromJson(Map<String, dynamic> json) {
    return CableTieGroup(
      id: readStringOr(json['id'], ''),
      position: readOffset(json['position']) ?? Offset.zero,
      memberConnectionIds: readStrings(json['memberConnectionIds']),
    );
  }

  /// Descarta entradas sem id, sem `position` válida ou sem nenhuma corda
  /// (o host descarta abraçadeira vazia).
  static List<CableTieGroup> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (readMap(e) case final m?)
          if (readOffset(m['position']) != null) CableTieGroup.fromJson(m),
    ].where((t) => t.id.isNotEmpty && t.memberConnectionIds.isNotEmpty).toList();
  }
}
