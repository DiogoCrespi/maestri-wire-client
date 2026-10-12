import 'dart:convert';
import '../../models/agent_role.dart';
import 'wire_client.dart';

/// Erro devolvido pelo host em rotas de responsabilidade (400, 404, 409...).
class RolesApiException implements Exception {
  final int statusCode;
  final String message;

  const RolesApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Responsabilidades de agente e a responsabilidade de um terminal.
/// Capability `roleManagement`.
extension RolesApi on WireClient {
  /// `GET /api/roles`
  Future<List<AgentRole>> listRoles() async {
    final json = await getJson('/api/roles');
    final raw = json['roles'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AgentRole.fromJson)
        .toList();
  }

  /// `POST /api/roles`. Devolve a responsabilidade como o host guardou.
  Future<AgentRole> createRole(RoleWrite write) async {
    final json = await _sendRoleJson('POST', '/api/roles', write.toJson());
    return AgentRole.fromJson(json);
  }

  /// `PUT /api/roles/{id}`. Substituição completa: reenvie `workspaceId`.
  /// Um prompt alterado reinicia os terminais em execução que a usam.
  Future<AgentRole> updateRole(String id, RoleWrite write) async {
    final json = await _sendRoleJson('PUT', '/api/roles/$id', write.toJson());
    return AgentRole.fromJson(json);
  }

  /// `DELETE /api/roles/{id}`. Remove a responsabilidade de onde estiver atribuída.
  Future<void> deleteRole(String id) async {
    await _sendRoleJson('DELETE', '/api/roles/$id', null);
  }

  /// `GET /api/terminals/{id}/settings` (somente leitura).
  Future<TerminalSettings> getTerminalSettings(String terminalId) async {
    final json = await getJson('/api/terminals/$terminalId/settings');
    return TerminalSettings.fromJson(json);
  }

  /// Troca a responsabilidade de um terminal. Lê as configurações atuais e
  /// reenvia todos os campos no PUT, porque é substituição completa.
  /// `roleId` null remove a responsabilidade. Um terminal em execução reinicia.
  Future<TerminalSettings> setTerminalRole(String terminalId, String? roleId) async {
    final current = await getTerminalSettings(terminalId);
    final body = current.toPutBody(roleId: roleId);
    final json = await _sendRoleJson(
      'PUT',
      '/api/terminals/$terminalId/settings',
      body,
    );
    return TerminalSettings.fromJson(json);
  }

  Future<Map<String, dynamic>> _sendRoleJson(String method, String path, Object? body) async {
    final res = await sendJson(method, path, body);
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw RolesApiException(res.statusCode, _errorMessage(res.statusCode, text));
    }
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static String _errorMessage(int status, String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        // formato real do host: {"error": {"code": ..., "message": ...}}
        final err = decoded['error'];
        final msg = err is Map ? err['message'] : (err ?? decoded['message']);
        if (msg is String && msg.isNotEmpty) return msg;
      }
    } catch (_) {
      // corpo não é JSON: cai na mensagem genérica
    }
    switch (status) {
      case 400:
        return 'Dados inválidos. Confira nome, prompt e cor.';
      case 409:
        return 'Já existe uma responsabilidade com este nome.';
      case 404:
        return 'Não encontrado no host.';
      default:
        return 'O host respondeu $status.';
    }
  }
}
