import 'dart:convert';
import 'dart:io';
import '../../models/floor.dart';
import 'wire_client.dart';

/// Erro devolvido pelo host, no formato `{"error": {"code": "...", "message": "..."}}`.
/// Usado por todas as rotas de workspace, andar, hooks e pull request.
class FloorApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const FloorApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  factory FloorApiException.fromResponse(int statusCode, String body) {
    String code = 'http$statusCode';
    String message = 'HTTP $statusCode';
    try {
      final decoded = jsonDecode(body);
      final err = decoded is Map ? decoded['error'] : null;
      if (err is Map) {
        if (err['code'] is String) code = err['code'] as String;
        if (err['message'] is String) message = err['message'] as String;
      }
    } catch (_) {
      if (body.trim().isNotEmpty) message = body.trim();
    }
    return FloorApiException(statusCode: statusCode, code: code, message: message);
  }

  /// Mensagem para o usuário: a própria palavra do host, com o status.
  String get userMessage => '$message (HTTP $statusCode)';

  @override
  String toString() => 'FloorApiException($statusCode $code): $message';
}

final _getErrorPattern = RegExp(r'respondeu (\d{3}): ([\s\S]*)$');

/// GET JSON que devolve [FloorApiException] em erro. `WireClient.getJson` lança
/// `HttpException` com o status no texto; aqui ele é reconvertido.
Future<Map<String, dynamic>> hostGetJson(WireClient client, String path) async {
  try {
    return await client.getJson(path);
  } on HttpException catch (e) {
    final m = _getErrorPattern.firstMatch(e.message);
    if (m == null) rethrow;
    throw FloorApiException.fromResponse(int.parse(m.group(1)!), m.group(2)!);
  }
}

/// Escrita JSON (POST, PUT, DELETE) que devolve o corpo decodificado ou lança
/// [FloorApiException]. Um corpo vazio vira mapa vazio.
Future<Map<String, dynamic>> hostRequestJson(
  WireClient client,
  String method,
  String path, [
  Map<String, dynamic>? body,
]) async {
  final res = await client.sendJson(method, path, body ?? const <String, dynamic>{});
  final text = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 200 && res.statusCode < 300) {
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }
  throw FloorApiException.fromResponse(res.statusCode, text);
}

/// `/api/workspaces/{ws}/floors/{floorValue}/{action}`. `floorValue` é o UUID do
/// andar ou `ground`.
String floorPath(String workspaceId, String floorValue, String action) =>
    '/api/workspaces/${Uri.encodeComponent(workspaceId)}/floors/${Uri.encodeComponent(floorValue)}/$action';

/// Prévia de aterrissagem (`FloorLanding`): o que a folha de aterrissagem mostra.
class LandingFile {
  final String path;
  final int additions;
  final int deletions;
  final bool isBinary;

  const LandingFile({
    required this.path,
    this.additions = 0,
    this.deletions = 0,
    this.isBinary = false,
  });

  factory LandingFile.fromJson(Map<String, dynamic> json) => LandingFile(
        path: json['path'] is String ? json['path'] as String : '?',
        additions: _int(json['additions']),
        deletions: _int(json['deletions']),
        isBinary: json['isBinary'] == true,
      );
}

class FloorLanding {
  /// Branch com checkout no clone do andar.
  final String? branch;

  /// Branch do térreo.
  final String? groundBranch;

  /// Branches locais do projeto.
  final List<String> branches;

  /// Alvo pré-visualizado (o pedido, senão o próprio do andar).
  final String? target;

  /// Se aterrissar em [target] faz merge em vez de só trazer o branch.
  final bool isMerge;
  final int commitCount;
  final List<LandingFile> files;

  /// Caminhos que um merge deixaria em conflito.
  final List<String> conflicts;

  const FloorLanding({
    this.branch,
    this.groundBranch,
    this.branches = const [],
    this.target,
    this.isMerge = false,
    this.commitCount = 0,
    this.files = const [],
    this.conflicts = const [],
  });

  bool get hasConflicts => conflicts.isNotEmpty;

  factory FloorLanding.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? raw) => raw is List
        ? [for (final e in raw) if (e is String) e]
        : const [];
    final files = json['files'];
    return FloorLanding(
      branch: _str(json['branch']),
      groundBranch: _str(json['groundBranch']),
      branches: strings(json['branches']),
      target: _str(json['target']),
      isMerge: json['isMerge'] == true,
      commitCount: _int(json['commitCount']),
      files: files is List
          ? [for (final f in files) if (f is Map) LandingFile.fromJson(Map<String, dynamic>.from(f))]
          : const [],
      conflicts: strings(json['conflicts']),
    );
  }
}

String? _str(Object? raw) {
  if (raw is! String) return null;
  final t = raw.trim();
  return t.isEmpty ? null : t;
}

int _int(Object? raw) => raw is int ? raw : (raw is num ? raw.toInt() : 0);

/// Rotas de andar do host (owner para escrita).
/// Contrato: notes/maestri-wire.md, seções "Andares" e "Status do andar".
extension FloorsApi on WireClient {
  /// GET /api/workspaces/{ws}/feed?floor=...
  /// `floor` null omite o parâmetro (espelha o andar ativo do host);
  /// senão use `FloorMeta.queryValue` (UUID ou `ground`).
  Future<Map<String, dynamic>> getFloorFeed(String workspaceId, {String? floor}) {
    final query = floor == null ? '' : '?floor=${Uri.encodeQueryComponent(floor)}';
    return getJson('/api/workspaces/${Uri.encodeComponent(workspaceId)}/feed$query');
  }

  /// Lista de andares do feed (`floors`), térreo primeiro como vem do host.
  Future<List<FloorMeta>> getFloors(String workspaceId, {String? floor}) async {
    final feed = await getFloorFeed(workspaceId, floor: floor);
    return FloorMeta.listFromJson(feed['floors']);
  }

  /// POST …/floors/{floor|ground}/activate. ESCRITA VISÍVEL: troca o andar ativo
  /// do host. Só por ação explícita. Erro (ex.: 404 neste host) vira [FloorApiException].
  Future<void> activateFloor(String workspaceId, FloorMeta floor) async {
    await hostRequestJson(this, 'POST', floorPath(workspaceId, floor.queryValue, 'activate'));
  }

  /// POST /api/workspaces/{ws}/floors — Novo Andar. Retorna o id criado (ou null
  /// quando o host não o devolve, como no andar pendente).
  Future<String?> createFloor(
    String workspaceId, {
    required String name,
    bool gitIsolation = true,
  }) async {
    final body = await hostRequestJson(
      this,
      'POST',
      '/api/workspaces/${Uri.encodeComponent(workspaceId)}/floors',
      {'name': name.trim(), 'gitIsolation': gitIsolation},
    );
    return body['floorId'] is String ? body['floorId'] as String : null;
  }

  /// POST …/floors/{id}/update — renomeia o andar (sem espaços nas pontas).
  Future<void> renameFloor(String workspaceId, FloorMeta floor, String name) async {
    await hostRequestJson(this, 'POST', floorPath(workspaceId, floor.queryValue, 'update'),
        {'name': name.trim()});
  }

  /// POST …/floors/{id|ground}/status — substitui o relato inteiro.
  /// `state` é working, blocked, review ou done. `progress` é 0…1.
  /// O `author` não é enviado: a edição é manual.
  Future<void> setFloorStatus(
    String workspaceId,
    FloorMeta floor, {
    required String state,
    required String text,
    double? progress,
  }) async {
    await hostRequestJson(this, 'POST', floorPath(workspaceId, floor.queryValue, 'status'), {
      'status': {
        'state': state,
        'text': text.trim(),
        if (progress != null) 'progress': progress,
      },
    });
  }

  /// POST …/floors/{id|ground}/status com `{status: null}`: limpa o relato.
  Future<void> clearFloorStatus(String workspaceId, FloorMeta floor) async {
    await hostRequestJson(this, 'POST', floorPath(workspaceId, floor.queryValue, 'status'),
        {'status': null});
  }

  /// POST …/floors/{id|ground}/unload — para os terminais do andar.
  Future<void> unloadFloor(String workspaceId, FloorMeta floor) async {
    await hostRequestJson(this, 'POST', floorPath(workspaceId, floor.queryValue, 'unload'));
  }

  /// GET …/floors/{id}/landing?target= — prévia do que aterrissar faria.
  /// Só lê; não muda nada no host. `target` null usa o alvo do próprio andar.
  Future<FloorLanding> getLandingPreview(
    String workspaceId,
    FloorMeta floor, {
    String? target,
  }) async {
    final query = target == null ? '' : '?target=${Uri.encodeQueryComponent(target)}';
    final json = await hostGetJson(this, '${floorPath(workspaceId, floor.queryValue, 'landing')}$query');
    return FloorLanding.fromJson(json);
  }

  /// POST …/floors/{id}/land — aterrissa. Campos ausentes são omitidos.
  /// Uma recusa que precisa de pessoa (trabalho não commitado, conflito) é 409
  /// com as palavras do host; o chamador mostra e não tenta de novo sozinho.
  Future<Map<String, dynamic>> landFloor(
    String workspaceId,
    FloorMeta floor, {
    String? targetBranch,
    bool deleteBranch = false,
    bool keepFloor = false,
  }) {
    return hostRequestJson(this, 'POST', floorPath(workspaceId, floor.queryValue, 'land'), {
      if (targetBranch != null) 'targetBranch': targetBranch,
      if (deleteBranch) 'deleteBranch': true,
      if (keepFloor) 'keepFloor': true,
    });
  }

  /// POST …/floors/{id}/delete — exclui o andar. `force` remove mesmo se o clone não sai.
  Future<void> deleteFloor(
    String workspaceId,
    FloorMeta floor, {
    bool deleteBranch = false,
    bool force = false,
  }) async {
    await hostRequestJson(this, 'POST', floorPath(workspaceId, floor.queryValue, 'delete'), {
      'deleteBranch': deleteBranch,
      if (force) 'force': true,
    });
  }
}

/// Texto de erro para mostrar à pessoa. Para erros do host, são as palavras
/// dele (ex.: a recusa 409 que nomeia os arquivos) com o status.
String hostErrorText(Object e) {
  if (e is FloorApiException) return e.userMessage;
  return e.toString().replaceAll('Exception: ', '').replaceAll('HttpException: ', '');
}
