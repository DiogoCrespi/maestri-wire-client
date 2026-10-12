import 'json_values.dart';

/// Payload `connector`: a plaquinha que representa um terminal em outro andar
/// (ou, com [remoteWorkspaceId], em outro workspace).
class ConnectorNode {
  final String remoteTerminalId;
  final String? remoteFloorId;
  final String? remoteWorkspaceId;

  const ConnectorNode({
    required this.remoteTerminalId,
    this.remoteFloorId,
    this.remoteWorkspaceId,
  });

  bool get isCrossWorkspace => remoteWorkspaceId != null;

  factory ConnectorNode.fromJson(Map<String, dynamic> json) {
    return ConnectorNode(
      remoteTerminalId: readStringOr(json['remoteTerminalId'], ''),
      remoteFloorId: readString(json['remoteFloorId']),
      remoteWorkspaceId: readString(json['remoteWorkspaceId']),
    );
  }

  /// Descarta entradas sem `remoteTerminalId` não vazio.
  static List<ConnectorNode> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (readMap(e) case final m?) ConnectorNode.fromJson(m),
    ].where((c) => c.remoteTerminalId.isNotEmpty).toList();
  }
}
