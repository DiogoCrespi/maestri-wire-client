import 'dart:convert';
import 'dart:io';

import '../../models/device.dart';
import 'wire_client.dart';

/// Dispositivos pareados do host. Capabilities `deviceRoles` e `deviceRenaming`.
/// Contrato: notes/maestri-wire.md, seção "Dispositivos".
extension DevicesApi on WireClient {
  /// `GET /api/devices`
  Future<List<PairedDevice>> listDevices() async {
    final json = await getJson('/api/devices');
    return PairedDevice.listFromJson(json);
  }

  /// `PUT /api/devices/{id}/name` com `{name}`. O nome é validado antes de sair.
  Future<void> renameDevice(String id, String name) => _expectOk(
        sendJson(
            'PUT', devicePath(id, 'name'), {'name': normalizeDeviceName(name)}),
      );

  /// `PUT /api/devices/{id}/role` com `{role}`. 409 se o dispositivo aponta
  /// para si mesmo e pediu `guest`.
  Future<void> setDeviceRole(String id, String role) {
    if (role != PairedDevice.roleOwner && role != PairedDevice.roleGuest) {
      throw ArgumentError('Papel inválido: $role');
    }
    return _expectOk(sendJson('PUT', devicePath(id, 'role'), {'role': role}));
  }

  /// `DELETE /api/devices/{id}`: revoga. Um dispositivo pode revogar a si mesmo.
  Future<void> revokeDevice(String id) =>
      _expectOk(sendJson('DELETE', devicePath(id), null));
}

/// Caminho de `/api/devices/{id}` com o sufixo opcional (`role`, `name`).
String devicePath(String id, [String? suffix]) {
  final base = '/api/devices/${Uri.encodeComponent(id)}';
  return suffix == null ? base : '$base/$suffix';
}

Future<void> _expectOk(Future<HttpClientResponse> pending) async {
  final response = await pending;
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(_errorMessage(response.statusCode, text));
  }
}

String _errorMessage(int status, String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['error'] is Map) {
      final err = decoded['error'] as Map;
      final message = err['message'] ?? err['code'];
      if (message != null) return '$message (HTTP $status)';
    }
  } catch (_) {
    // corpo não é JSON
  }
  return 'Host respondeu HTTP $status${text.isEmpty ? '' : ': $text'}';
}
