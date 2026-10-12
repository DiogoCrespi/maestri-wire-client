/// Partitura: arranjo de canvas salvo no host (`GET /api/partituras`).
/// Criar e editar continuam no host; o cliente só lista, prévia e estampa.
class PartituraRole {
  final String id;
  final String name;
  final String icon;
  final String color;

  const PartituraRole({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });

  factory PartituraRole.fromJson(Map<String, dynamic> json) => PartituraRole(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        icon: (json['icon'] ?? '').toString(),
        color: (json['color'] ?? '').toString(),
      );
}

class Partitura {
  final String id;
  final String name;
  final String summary;
  final String icon;
  final String color;
  final String? workspaceId;
  final List<PartituraRole> roles;

  const Partitura({
    required this.id,
    required this.name,
    this.summary = '',
    this.icon = '',
    this.color = '',
    this.workspaceId,
    this.roles = const [],
  });

  factory Partitura.fromJson(Map<String, dynamic> json) {
    final ws = json['workspaceId'];
    final rawRoles = json['roles'];
    return Partitura(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
      color: (json['color'] ?? '').toString(),
      workspaceId: ws is String && ws.isNotEmpty ? ws : null,
      roles: rawRoles is List
          ? rawRoles
              .whereType<Map<String, dynamic>>()
              .map(PartituraRole.fromJson)
              .toList()
          : const [],
    );
  }

  /// Lê o corpo de `GET /api/partituras` (`{partituras: [...]}`).
  static List<Partitura> listFromJson(Map<String, dynamic> json) {
    final raw = json['partituras'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Partitura.fromJson)
        .where((p) => p.id.isNotEmpty)
        .toList();
  }
}
