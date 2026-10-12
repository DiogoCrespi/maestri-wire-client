/// Dispositivo pareado (`GET /api/devices`). Pertence ao host.
///
/// `role` é `owner` (Controle total) ou `guest` (Somente leitura). Ausente ou
/// desconhecido vira null e a tela trata como indefinido.
class PairedDevice {
  static const roleOwner = 'owner';
  static const roleGuest = 'guest';

  final String id;
  final String name;
  final String? lastSeenIP;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final String? role;

  const PairedDevice({
    required this.id,
    required this.name,
    this.lastSeenIP,
    this.lastSeenAt,
    this.createdAt,
    this.role,
  });

  bool get isOwner => role == roleOwner;
  bool get isGuest => role == roleGuest;

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    String? text(Object? raw) {
      if (raw is! String) return null;
      final t = raw.trim();
      return t.isEmpty ? null : t;
    }

    final rawRole = text(json['role']);
    return PairedDevice(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      lastSeenIP: text(json['lastSeenIP']),
      lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      role: rawRole == roleOwner || rawRole == roleGuest ? rawRole : null,
    );
  }

  /// Lê o corpo completo de `GET /api/devices` (`{devices: [...]}`).
  static List<PairedDevice> listFromJson(Map<String, dynamic> json) {
    final raw = json['devices'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(PairedDevice.fromJson)
        .where((d) => d.id.isNotEmpty)
        .toList();
  }
}

/// Valida um nome de dispositivo como o host: espaços aparados, de 1 a 80
/// caracteres. Lança [ArgumentError] se inválido.
String normalizeDeviceName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) throw ArgumentError('O nome não pode ficar vazio.');
  if (name.length > 80) {
    throw ArgumentError('O nome pode ter no máximo 80 caracteres.');
  }
  return name;
}
