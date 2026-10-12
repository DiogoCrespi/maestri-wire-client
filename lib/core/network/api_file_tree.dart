import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/file_tree.dart';
import 'tls_pinning.dart';
import 'wire_client.dart';

/// Rotas de árvore de arquivos (capability `fileTrees`, somente owner).
///
/// Todas são leituras, exceto a criação de um nó `fileTree` ([createFileTreeNode]).
/// Os erros do host chegam como [FileTreeException].
extension FileTreeApi on WireClient {
  /// `GET …/nodes/{id}/tree?path=&hidden=`
  Future<FileTreeListing> getFileTreeListing({
    required String workspaceId,
    required String nodeId,
    String path = '',
    bool? hidden,
  }) async {
    final query = <String>['path=${Uri.encodeQueryComponent(path)}'];
    if (hidden != null) query.add('hidden=$hidden');
    final json = await _fileTreeGet(
      '/api/workspaces/$workspaceId/nodes/$nodeId/tree?${query.join('&')}',
    );
    return FileTreeListing.fromJson(json);
  }

  /// `GET …/nodes/{id}/tree/search?query=&hidden=`
  Future<FileTreeSearch> searchFileTree({
    required String workspaceId,
    required String nodeId,
    required String query,
    bool? hidden,
  }) async {
    final parts = <String>['query=${Uri.encodeQueryComponent(query)}'];
    if (hidden != null) parts.add('hidden=$hidden');
    final json = await _fileTreeGet(
      '/api/workspaces/$workspaceId/nodes/$nodeId/tree/search?${parts.join('&')}',
    );
    return FileTreeSearch.fromJson(json);
  }

  /// `GET …/nodes/{id}/tree/changes`. `404` quando a raiz não está num repositório.
  Future<FileTreeChanges> getFileTreeChanges({
    required String workspaceId,
    required String nodeId,
  }) async {
    final json = await _fileTreeGet(
      '/api/workspaces/$workspaceId/nodes/$nodeId/tree/changes',
    );
    return FileTreeChanges.fromJson(json);
  }

  /// `GET …/nodes/{id}/tree/diff?path=&scope=`
  Future<FileTreeDiff> getFileTreeDiff({
    required String workspaceId,
    required String nodeId,
    required String path,
    FileTreeDiffScope scope = FileTreeDiffScope.combined,
  }) async {
    final json = await _fileTreeGet(
      '/api/workspaces/$workspaceId/nodes/$nodeId/tree/diff'
      '?path=${Uri.encodeQueryComponent(path)}&scope=${scope.wire}',
    );
    return FileTreeDiff.fromJson(json);
  }

  /// `GET /api/workspaces/{ws}/directories?prefix=` : pastas que completam um caminho.
  Future<List<String>> suggestDirectories({
    required String workspaceId,
    required String prefix,
  }) async {
    final json = await _fileTreeGet(
      '/api/workspaces/$workspaceId/directories?prefix=${Uri.encodeQueryComponent(prefix)}',
    );
    final dirs = json['directories'];
    return dirs is List ? dirs.whereType<String>().toList() : const [];
  }

  /// `POST …/nodes` com kind `fileTree` e `path`. Devolve o id do nó criado.
  Future<String> createFileTreeNode({
    required String workspaceId,
    required String path,
    double? x,
    double? y,
  }) async {
    final body = <String, Object?>{'kind': 'fileTree', 'path': path};
    if (x != null) body['x'] = x;
    if (y != null) body['y'] = y;
    final res = await sendJson('POST', '/api/workspaces/$workspaceId/nodes', body);
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw FileTreeException.fromResponse(res.statusCode, text);
    final json = jsonDecode(text) as Map<String, dynamic>;
    final id = json['nodeId'];
    if (id is! String) throw const FileTreeException(statusCode: 200, code: 'invalidResponse', message: 'nodeId ausente');
    return id;
  }

  /// Bytes de um arquivo da árvore. Com [start]/[end] envia `Range` (206 ou 416).
  /// [end] é inclusivo, como no HTTP. Sem [end], lê até o fim a partir de [start].
  Future<FileTreeBytes> getFileTreeBytes({
    required String workspaceId,
    required String nodeId,
    required String path,
    int? start,
    int? end,
  }) =>
      _fetchFileTreeBytes(
        this,
        workspaceId: workspaceId,
        nodeId: nodeId,
        path: path,
        start: start,
        end: end,
      );

  Future<Map<String, dynamic>> _fileTreeGet(String pathAndQuery) async {
    try {
      return await getJson(pathAndQuery);
    } on HttpException catch (e) {
      // getJson formata "GET <path> respondeu <status>: <corpo>"
      final match = RegExp(r'respondeu (\d+): ([\s\S]*)$').firstMatch(e.message);
      if (match == null) rethrow;
      throw FileTreeException.fromResponse(int.parse(match.group(1)!), match.group(2)!);
    }
  }
}

/// Requisição de bytes com `Range`. Usa o mesmo TLS fixado do cliente, mas
/// lê o corpo como bytes (o `getJson` só decodifica JSON).
Future<FileTreeBytes> _fetchFileTreeBytes(
  WireClient client, {
  required String workspaceId,
  required String nodeId,
  required String path,
  int? start,
  int? end,
}) async {
  final pair = client.currentPairData;
  if (pair == null) throw Exception('Host não configurado');

  final http = createPinnedHttpClient(expectedPin: pair.serverKeyHash);
  try {
    final uri = Uri.parse(
      '${pair.baseUrl}/api/workspaces/$workspaceId/nodes/$nodeId/tree/file'
      '?path=${Uri.encodeQueryComponent(path)}',
    );
    final request = await http.getUrl(uri);
    final token = client.authToken;
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.headers.set(HttpHeaders.hostHeader, pair.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');
    if (start != null) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-${end ?? ''}');
    }

    final response = await request.close();
    if (response.statusCode == 416) {
      // Range além do fim: trecho vazio, com o total para o chamador parar.
      await response.drain<void>();
      return FileTreeBytes(
        bytes: const [],
        statusCode: 416,
        totalLength: parseContentRangeTotal(response.headers.value(HttpHeaders.contentRangeHeader)),
        start: start ?? 0,
      );
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      final body = await response.transform(utf8.decoder).join();
      throw FileTreeException.fromResponse(response.statusCode, body);
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return FileTreeBytes(
      bytes: builder.takeBytes(),
      statusCode: response.statusCode,
      contentType: response.headers.contentType?.mimeType,
      totalLength: parseContentRangeTotal(response.headers.value(HttpHeaders.contentRangeHeader)),
      start: start ?? 0,
    );
  } finally {
    http.close(force: true);
  }
}
