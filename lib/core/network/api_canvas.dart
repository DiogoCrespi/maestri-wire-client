import 'dart:convert';

import 'wire_client.dart';

/// Falha de uma escrita no canvas. `code` é o `error.code` do host (ex.: `conflict`, `invalidRequest`).
class CanvasWriteException implements Exception {
  final int status;
  final String code;
  final String message;

  const CanvasWriteException(this.status, this.code, this.message);

  @override
  String toString() => message;
}

/// Escritas do canvas (capability `canvasWrites`, somente owner).
/// Todas repetem os ids literalmente e respondem `{ok: true}` ou um corpo com o id criado.
extension CanvasApi on WireClient {
  Future<Map<String, dynamic>> _canvasWrite(String method, String path, [Map<String, dynamic>? body]) async {
    final res = await sendJson(method, path, body);
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode > 299) {
      var code = 'unknown';
      var message = 'Falha no host (${res.statusCode})';
      try {
        final err = (jsonDecode(text) as Map<String, dynamic>)['error'];
        if (err is Map) {
          code = (err['code'] ?? code).toString();
          message = (err['message'] ?? message).toString();
        }
      } catch (_) {}
      throw CanvasWriteException(res.statusCode, code, message);
    }
    if (text.isEmpty) return {'ok': true};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : {'ok': true};
  }

  /// Grava o frame (posição e tamanho) do nó no host. O host encaixa na grade e responde o frame guardado.
  /// `409` quando o nó está travado.
  Future<Map<String, dynamic>> moveNode({
    required String workspaceId,
    required String nodeId,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    return _canvasWrite(
      'POST',
      '/api/workspaces/$workspaceId/nodes/$nodeId/frame',
      {'x': x.round(), 'y': y.round(), 'width': width.round(), 'height': height.round()},
    );
  }

  Future<void> renameNode({required String workspaceId, required String nodeId, required String name}) async {
    await _canvasWrite('POST', '/api/workspaces/$workspaceId/nodes/$nodeId/rename', {'name': name});
  }

  Future<void> setNodeLocked({required String workspaceId, required String nodeId, required bool locked}) async {
    await _canvasWrite('POST', '/api/workspaces/$workspaceId/nodes/$nodeId/lock', {'locked': locked});
  }

  /// Duplica o nó e devolve o id da cópia.
  Future<String> duplicateNode({required String workspaceId, required String nodeId}) async {
    final res = await _canvasWrite('POST', '/api/workspaces/$workspaceId/nodes/$nodeId/duplicate');
    return (res['nodeId'] ?? '').toString();
  }

  /// Cria uma nota de texto (kind `text`) em x,y do canvas.
  Future<String> createTextNode({
    required String workspaceId,
    required double x,
    required double y,
    String text = '',
  }) async {
    final res = await _canvasWrite('POST', '/api/workspaces/$workspaceId/nodes', {
      'kind': 'text',
      'x': x.round(),
      'y': y.round(),
      'text': text,
    });
    return (res['nodeId'] ?? '').toString();
  }

  /// Exclui um nó. Os terminais, portais e fichários seguem as regras do host.
  Future<void> deleteNode({required String workspaceId, required String nodeId}) async {
    await _canvasWrite('DELETE', '/api/workspaces/$workspaceId/nodes/$nodeId');
  }

  /// Exclui uma seleção numa única requisição (um passo de desfazer no host). Todo id precisa existir.
  Future<void> deleteNodes({required String workspaceId, required List<String> nodeIds}) async {
    await _canvasWrite('POST', '/api/workspaces/$workspaceId/nodes/delete', {'nodeIds': nodeIds});
  }

  /// Liga dois nós com uma corda. `toNodeId` pode ser um connector.
  Future<void> createConnection({
    required String workspaceId,
    required String fromNodeId,
    required String toNodeId,
  }) async {
    await _canvasWrite('POST', '/api/workspaces/$workspaceId/connections', {
      'fromNodeId': fromNodeId,
      'toNodeId': toNodeId,
    });
  }

  /// Desconecta um par de nós. O host recusa pontas de connector (`400`): nesse caso exclua o connector.
  Future<void> deleteConnection({
    required String workspaceId,
    required String fromNodeId,
    required String toNodeId,
  }) async {
    await _canvasWrite('DELETE', '/api/workspaces/$workspaceId/connections', {
      'fromNodeId': fromNodeId,
      'toNodeId': toNodeId,
    });
  }

  /// Agrupa nós (dois ou mais). Devolve o id do grupo quando o host informa.
  Future<String?> createGroup({
    required String workspaceId,
    required List<String> nodeIds,
    String? name,
  }) async {
    final res = await _canvasWrite('POST', '/api/workspaces/$workspaceId/groups', {
      'nodeIds': nodeIds,
      'drawingIds': <String>[],
      if (name != null && name.isNotEmpty) 'name': name,
    });
    return res['groupId'] as String?;
  }

  /// Desagrupa nós e desenhos. Os membros ficam onde estão.
  Future<void> ungroup({
    required String workspaceId,
    required List<String> nodeIds,
    List<String> drawingIds = const [],
  }) async {
    await _canvasWrite('POST', '/api/workspaces/$workspaceId/ungroup', {
      'nodeIds': nodeIds,
      'drawingIds': drawingIds,
    });
  }

  Future<void> deleteGroup({required String workspaceId, required String groupId}) async {
    await _canvasWrite('DELETE', '/api/workspaces/$workspaceId/groups/$groupId');
  }

  /// Revela o nó no host (app para frente, workspace e andar ativos, câmera no nó).
  Future<void> focusNode({required String workspaceId, required String nodeId}) async {
    await _canvasWrite('POST', '/api/workspaces/$workspaceId/nodes/$nodeId/focus');
  }

  // Abraçadeiras (cableTies): cria com as cordas do andar, reposiciona e corta.
  Future<void> createTie({
    required String workspaceId,
    required String tieId,
    required double x,
    required double y,
    required List<String> memberConnectionIds,
    String? floorId,
  }) async {
    await _canvasWrite('POST', '/api/workspaces/$workspaceId/ties', {
      if (floorId != null) 'floorId': floorId,
      'tie': {
        'id': tieId,
        'position': {'x': x, 'y': y},
        'memberConnectionIds': memberConnectionIds,
      },
    });
  }

  Future<void> moveTie({required String workspaceId, required String tieId, required double x, required double y}) async {
    await _canvasWrite('POST', '/api/workspaces/$workspaceId/ties/$tieId/position', {'x': x, 'y': y});
  }

  Future<void> deleteTie({required String workspaceId, required String tieId}) async {
    await _canvasWrite('DELETE', '/api/workspaces/$workspaceId/ties/$tieId');
  }
}
