import '../../models/floor.dart';
import '../../models/pull_request.dart';
import 'api_floors.dart';
import 'wire_client.dart';

/// Pull requests do andar (owner). Contrato: notes/maestri-wire.md, "Andares",
/// seção pull-request. Operações de um andar correm uma de cada vez: outra em
/// curso é 409. Erros viram [FloorApiException] com o status (412 pede
/// confirmação de remoção; 409 e 503 trazem as palavras do host).
extension PullRequestsApi on WireClient {
  String _prPath(String ws, FloorMeta floor, String action) =>
      floorPath(ws, floor.queryValue, 'pull-request${action.isEmpty ? '' : '/$action'}');

  /// GET …/pull-request/context?base=
  Future<PullRequestContext> getPullRequestContext(
    String workspaceId,
    FloorMeta floor, {
    String? base,
  }) async {
    final query = base == null ? '' : '?base=${Uri.encodeQueryComponent(base)}';
    final json = await hostGetJson(this, '${_prPath(workspaceId, floor, 'context')}$query');
    return PullRequestContext.fromJson(json);
  }

  /// POST …/pull-request — faz push e abre o pull request.
  /// `onWebsite` só depois de um 502 do provedor (o host confirma se é possível).
  Future<PullRequestOpened> openPullRequest(
    String workspaceId,
    FloorMeta floor, {
    required String base,
    required String title,
    String body = '',
    bool? draft,
    bool? onWebsite,
  }) async {
    final json = await hostRequestJson(
      this,
      'POST',
      _prPath(workspaceId, floor, ''),
      pullRequestOpenBody(
        base: base,
        title: title,
        body: body,
        draft: draft,
        onWebsite: onWebsite,
      ),
    );
    return PullRequestOpened.fromJson(json);
  }

  /// POST …/pull-request/check — o resultado chega pelo feed.
  Future<void> checkPullRequest(String workspaceId, FloorMeta floor) async {
    await hostRequestJson(this, 'POST', _prPath(workspaceId, floor, 'check'));
  }

  /// POST …/pull-request/merge {method}. `method` é um de `mergeMethods`.
  Future<void> mergePullRequest(
    String workspaceId,
    FloorMeta floor, {
    required String method,
    String? recordId,
  }) async {
    await hostRequestJson(this, 'POST', _prPath(workspaceId, floor, 'merge'), {
      'method': method,
      if (recordId != null) 'recordId': recordId,
    });
  }

  /// POST …/pull-request/push — envia os commits novos ao pull request.
  Future<void> pushPullRequest(String workspaceId, FloorMeta floor, {String? recordId}) async {
    await hostRequestJson(this, 'POST', _prPath(workspaceId, floor, 'push'), {
      if (recordId != null) 'recordId': recordId,
    });
  }

  /// POST …/pull-request/remove. Um 412 significa trabalho extra no andar: a
  /// pessoa confirma e a chamada é refeita com `confirmExtraWork: true`.
  Future<PullRequestRemoved> removePullRequest(
    String workspaceId,
    FloorMeta floor, {
    bool confirmExtraWork = false,
    String? recordId,
  }) async {
    final json = await hostRequestJson(this, 'POST', _prPath(workspaceId, floor, 'remove'), {
      if (confirmExtraWork) 'confirmExtraWork': true,
      if (recordId != null) 'recordId': recordId,
    });
    return PullRequestRemoved.fromJson(json);
  }

  /// POST …/pull-request/hand-off — Perguntar a um Agente.
  Future<void> handOffPullRequest(
    String workspaceId,
    FloorMeta floor, {
    required String terminalId,
    required String task,
    String? note,
    String? recordId,
  }) async {
    await hostRequestJson(this, 'POST', _prPath(workspaceId, floor, 'hand-off'), {
      'terminalId': terminalId,
      'task': task,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (recordId != null) 'recordId': recordId,
    });
  }

  /// DELETE …/pull-request?record= — Abrir um Novo Pull Request, esquecendo o
  /// registro atual (fechado, ou aberto no site).
  Future<void> forgetPullRequest(String workspaceId, FloorMeta floor, {String? record}) async {
    final query = record == null ? '' : '?record=${Uri.encodeQueryComponent(record)}';
    await hostRequestJson(this, 'DELETE', '${_prPath(workspaceId, floor, '')}$query');
  }
}
