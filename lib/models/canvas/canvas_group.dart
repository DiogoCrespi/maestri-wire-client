import 'json_values.dart';

/// Grupo de nós do andar (`groups` do snapshot). Um nó nomeia seu grupo por `groupId`.
class CanvasGroup {
  final String id;
  final String name;
  final String? colorHex;

  const CanvasGroup({required this.id, this.name = '', this.colorHex});

  factory CanvasGroup.fromJson(Map<String, dynamic> json) {
    return CanvasGroup(
      id: readStringOr(json['id'], ''),
      name: readStringOr(json['name'], ''),
      colorHex: readString(json['colorHex']),
    );
  }

  /// Descarta entradas sem id.
  static List<CanvasGroup> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (readMap(e) case final m?) CanvasGroup.fromJson(m),
    ].where((g) => g.id.isNotEmpty).toList();
  }
}
