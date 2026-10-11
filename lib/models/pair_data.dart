import 'dart:convert';

/// Representa os dados codificados no QR Code do Maestri Wire (ou inseridos manualmente).
class PairData {
  final int protocolVersion;
  final String scheme;
  final String host;
  final int port;
  final String? pairingCode;
  final String? expiresAt;
  final String serverKeyHash;
  final List<String> alternateHosts;

  PairData({
    required this.protocolVersion,
    required this.scheme,
    required this.host,
    required this.port,
    this.pairingCode,
    this.expiresAt,
    required this.serverKeyHash,
    this.alternateHosts = const [],
  });

  String get baseUrl => '$scheme://$host:$port';

  PairData copyWith({
    String? host,
    int? port,
    String? serverKeyHash,
    List<String>? alternateHosts,
  }) {
    return PairData(
      protocolVersion: protocolVersion,
      scheme: scheme,
      host: host ?? this.host,
      port: port ?? this.port,
      pairingCode: pairingCode,
      expiresAt: expiresAt,
      serverKeyHash: serverKeyHash ?? this.serverKeyHash,
      alternateHosts: alternateHosts ?? this.alternateHosts,
    );
  }

  factory PairData.fromJson(Map<String, dynamic> json) {
    return PairData(
      protocolVersion: json['protocolVersion'] ?? 1,
      scheme: json['scheme'] ?? 'https',
      host: json['host'] ?? '127.0.0.1',
      port: json['port'] ?? 7434,
      pairingCode: json['pairingCode'],
      expiresAt: json['expiresAt'],
      serverKeyHash: json['serverKeyHash'] ?? '',
      alternateHosts: (json['alternateHosts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  factory PairData.fromQrString(String raw) {
    final Map<String, dynamic> data = jsonDecode(raw);
    return PairData.fromJson(data);
  }

  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'scheme': scheme,
        'host': host,
        'port': port,
        'pairingCode': pairingCode,
        'expiresAt': expiresAt,
        'serverKeyHash': serverKeyHash,
        'alternateHosts': alternateHosts,
      };
}

/// Resposta obtida com sucesso da rota POST /pair
class PairResponse {
  final String token;
  final String deviceId;
  final String deviceName;
  final int protocolVersion;
  final String role; // "owner" ou "guest"

  PairResponse({
    required this.token,
    required this.deviceId,
    required this.deviceName,
    required this.protocolVersion,
    required this.role,
  });

  bool get isOwner => role == 'owner';

  factory PairResponse.fromJson(Map<String, dynamic> json) {
    return PairResponse(
      token: json['token'] ?? '',
      deviceId: json['deviceId'] ?? '',
      deviceName: json['deviceName'] ?? '',
      protocolVersion: json['protocolVersion'] ?? 1,
      role: json['role'] ?? 'owner',
    );
  }
}
