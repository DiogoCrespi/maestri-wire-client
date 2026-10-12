import 'dart:convert';
import 'dart:io';

import '../../models/routine.dart';
import 'wire_client.dart';

/// Rotinas do host (capability `routines`, somente owner para escrita).
/// Contrato: notes/maestri-wire.md, seção "Rotinas".
extension RoutinesApi on WireClient {
  /// `GET /api/routines`: rotinas, histórico e alvos possíveis.
  Future<RoutinesSnapshot> listRoutines() async {
    final json = await getJson('/api/routines');
    return RoutinesSnapshot.fromJson(json);
  }

  /// `POST /api/routines`: cria sob o id do modelo. 409 se o id já existe.
  Future<void> createRoutine(Routine routine) =>
      _expectOk(sendJson('POST', '/api/routines', routine.toJson()));

  /// `PUT /api/routines/{id}`: substitui a rotina inteira.
  Future<void> updateRoutine(Routine routine) => _expectOk(
      sendJson('PUT', '/api/routines/${routine.id}', routine.toJson()));

  /// `DELETE /api/routines/{id}`.
  Future<void> deleteRoutine(String id) =>
      _expectOk(sendJson('DELETE', '/api/routines/$id'));

  /// `POST /api/routines/{id}/action`: run (Executar Agora), enable ou disable.
  Future<void> routineAction(String id, RoutineAction action) => _expectOk(
      sendJson('POST', '/api/routines/$id/action', {'action': action.wire}));

  /// `DELETE /api/routines/history`: limpa o histórico; as rotinas ficam intocadas.
  Future<void> clearRoutineHistory() =>
      _expectOk(sendJson('DELETE', '/api/routines/history'));
}

/// Lê a resposta, exige status 200 e o corpo `{"ok": true}` (ou erro estruturado).
Future<void> _expectOk(Future<HttpClientResponse> pending) async {
  final response = await pending;
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
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
    // corpo não é JSON: cai na mensagem genérica
  }
  return 'Host respondeu HTTP $status${text.isEmpty ? '' : ': $text'}';
}
