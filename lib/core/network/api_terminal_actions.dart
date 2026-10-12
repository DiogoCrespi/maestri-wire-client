import 'dart:convert';
import '../../models/terminal_appearance.dart';
import '../../models/terminal_settings.dart';
import 'wire_client.dart';

/// Erro devolvido pelo host em ações de terminal/conexão.
class TerminalActionException implements Exception {
  final int statusCode;
  final String message;

  const TerminalActionException({required this.statusCode, required this.message});

  factory TerminalActionException.fromResponse(int statusCode, String body) {
    var message = 'HTTP $statusCode';
    try {
      final decoded = jsonDecode(body);
      final err = decoded is Map ? decoded['error'] : null;
      if (err is Map && err['message'] is String) {
        message = err['message'] as String;
      } else if (err is String) {
        message = err;
      }
    } catch (_) {
      if (body.trim().isNotEmpty) message = body.trim();
    }
    return TerminalActionException(statusCode: statusCode, message: message);
  }

  @override
  String toString() => 'TerminalActionException($statusCode): $message';
}

String _enc(String s) => Uri.encodeComponent(s);

/// Ações sobre um terminal existente. Todas são escrita (owner no host).
/// Exclusão de nó: use `WireClient.deleteNode` (já existe em wire_client.dart).
extension TerminalActionsApi on WireClient {
  /// GET /api/terminals/{id}/settings
  Future<TerminalSettings> getTerminalSettings(String terminalId) async {
    final json = await getJson('/api/terminals/${_enc(terminalId)}/settings');
    return TerminalSettings.fromJson(json);
  }

  /// PUT /api/terminals/{id}/settings como substituição completa: lê o GET,
  /// troca só os campos informados e envia o resto como veio.
  /// Campos nulos mantêm o valor atual; `clear*` apaga. `appearance`, quando
  /// informada, substitui a aparência inteira (use `TerminalAppearance.copyWith`
  /// sobre `TerminalSettings.appearanceModel`).
  /// Atenção: trocar `roleId` reinicia um terminal em execução.
  Future<void> putTerminalSettings(
    String terminalId, {
    String? command,
    bool? maestroMode,
    bool? monitorActivity,
    String? icon,
    String? color,
    String? roleId,
    TerminalAppearance? appearance,
    bool clearRole = false,
    bool clearIcon = false,
    bool clearColor = false,
  }) async {
    final current = await getTerminalSettings(terminalId);
    final body = current.toPutBody(
      command: command,
      maestroMode: maestroMode,
      monitorActivity: monitorActivity,
      icon: icon,
      color: color,
      roleId: roleId,
      appearance: appearance,
      clearRole: clearRole,
      clearIcon: clearIcon,
      clearColor: clearColor,
    );
    await _send('PUT', '/api/terminals/${_enc(terminalId)}/settings', body);
  }

  /// POST /api/terminals/{id}/kill: encerra o processo.
  Future<void> killTerminal(String terminalId) =>
      _send('POST', '/api/terminals/${_enc(terminalId)}/kill', const <String, dynamic>{});

  /// POST /api/terminals/{id}/restart: o recarregar do host; acorda um terminal
  /// descarregado.
  Future<void> restartTerminal(String terminalId) =>
      _send('POST', '/api/terminals/${_enc(terminalId)}/restart', const <String, dynamic>{});

  /// POST /api/terminals/{id}/unload: o Descarregar do host. A sessão é
  /// desmontada e o scrollback fica preservado até um `restartTerminal`.
  Future<void> unloadTerminal(String terminalId) =>
      _send('POST', '/api/terminals/${_enc(terminalId)}/unload', const <String, dynamic>{});

  /// POST /api/terminals/{id}/focus: o host vai até o terminal.
  Future<void> focusTerminal(String terminalId) =>
      _send('POST', '/api/terminals/${_enc(terminalId)}/focus', const <String, dynamic>{});

  /// POST /api/workspaces/{ws}/connections: liga [fromNodeId] a [toNodeId].
  Future<void> connectNodes(String workspaceId, String fromNodeId, String toNodeId) =>
      _send(
        'POST',
        '/api/workspaces/${_enc(workspaceId)}/connections',
        {'fromNodeId': fromNodeId, 'toNodeId': toNodeId},
      );

  /// DELETE /api/workspaces/{ws}/connections: desfaz a corda entre os dois nós.
  Future<void> disconnectNodes(String workspaceId, String fromNodeId, String toNodeId) =>
      _send(
        'DELETE',
        '/api/workspaces/${_enc(workspaceId)}/connections',
        {'fromNodeId': fromNodeId, 'toNodeId': toNodeId},
      );

  Future<void> _send(String method, String path, Object body) async {
    final res = await sendJson(method, path, body);
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw TerminalActionException.fromResponse(res.statusCode, text);
  }
}
