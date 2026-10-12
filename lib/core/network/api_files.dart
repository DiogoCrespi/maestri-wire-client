import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tls_pinning.dart';
import 'wire_client.dart';

/// Limite de upload do host (`POST …/files`).
const int kMaxUploadBytes = 8 * 1024 * 1024;

/// Resposta de uma leitura de arquivo: bytes e o que o host respondeu.
class NodeFileBytes {
  final int statusCode;
  final Uint8List bytes;
  final String? contentType;
  final String? contentRange;
  final String? etag;

  const NodeFileBytes({
    required this.statusCode,
    required this.bytes,
    this.contentType,
    this.contentRange,
    this.etag,
  });

  /// Tamanho total do arquivo quando o host informa em `Content-Range: bytes a-b/total`.
  int? get totalLength {
    final range = contentRange;
    if (range == null) return null;
    final slash = range.lastIndexOf('/');
    if (slash < 0) return null;
    return int.tryParse(range.substring(slash + 1).trim());
  }
}

/// Coordenada sem `.0` quando é inteira (120 e não 120.0).
String _coord(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Monta `/api/workspaces/{ws}/files?filename=&x=&y=&floor=&mutationId=`.
/// Parâmetros ausentes ficam fora da query.
Uri buildFileUploadUri(
  String baseUrl, {
  required String workspaceId,
  required String filename,
  double? x,
  double? y,
  String? floorId,
  String? mutationId,
}) {
  final query = <String, String>{
    'filename': filename,
    if (x != null) 'x': _coord(x),
    if (y != null) 'y': _coord(y),
    if (floorId != null && floorId.isNotEmpty) 'floor': floorId,
    if (mutationId != null && mutationId.isNotEmpty) 'mutationId': mutationId,
  };
  return Uri.parse('$baseUrl/api/workspaces/$workspaceId/files').replace(queryParameters: query);
}

/// Sobe um arquivo para o canvas. O corpo é cru, sob o `contentType` informado.
/// Um `.md` ou `.txt` vira nota no host; outros viram nó de arquivo.
/// Retorna o `nodeId` criado. Lança `ArgumentError` acima de 8 MB, sem chamar o host.
Future<String> uploadWorkspaceFile({
  required WireClient client,
  required String workspaceId,
  required List<int> bytes,
  required String filename,
  String contentType = 'application/octet-stream',
  double? x,
  double? y,
  String? floorId,
  String? mutationId,
}) async {
  if (bytes.length > kMaxUploadBytes) {
    throw ArgumentError('Arquivo maior que 8 MB (${bytes.length} bytes).');
  }
  final res = await _raw(
    client,
    'POST',
    buildFileUploadUri(
      _baseUrl(client),
      workspaceId: workspaceId,
      filename: filename,
      x: x,
      y: y,
      floorId: floorId,
      mutationId: mutationId,
    ),
    body: bytes,
    contentType: contentType,
  );
  final text = utf8.decode(res.bytes, allowMalformed: true);
  if (res.statusCode != 200) {
    throw HttpException('POST files respondeu ${res.statusCode}: $text');
  }
  final json = jsonDecode(text);
  if (json is! Map<String, dynamic> || json['nodeId'] is! String) {
    throw HttpException('POST files devolveu um corpo inesperado: $text');
  }
  return json['nodeId'] as String;
}

/// `GET …/nodes/{id}/file`: bytes crus do arquivo. Com [rangeStart]/[rangeEnd] envia
/// `Range: bytes=start-end` e espera `206` (ou `416` quando fora do tamanho).
Future<NodeFileBytes> loadNodeFile({
  required WireClient client,
  required String workspaceId,
  required String nodeId,
  int? rangeStart,
  int? rangeEnd,
}) {
  final uri = Uri.parse('${_baseUrl(client)}/api/workspaces/$workspaceId/nodes/$nodeId/file');
  final range = rangeStart == null
      ? null
      : 'bytes=$rangeStart-${rangeEnd ?? ''}';
  return _read(client, uri, range: range);
}

/// `GET …/nodes/{id}/file/preview`: imagem reduzida (maior lado 1100px).
/// Com [etag] envia `If-None-Match`; `304` vem com `bytes` vazios. `404` quando o
/// arquivo não é uma imagem que o host decodifica. Leia o `contentType` (PNG ou JPEG).
Future<NodeFileBytes> loadNodePreview({
  required WireClient client,
  required String workspaceId,
  required String nodeId,
  String? etag,
}) {
  final uri = Uri.parse('${_baseUrl(client)}/api/workspaces/$workspaceId/nodes/$nodeId/file/preview');
  return _read(client, uri, ifNoneMatch: etag);
}

String _baseUrl(WireClient client) {
  final pair = client.currentPairData;
  if (pair == null) throw Exception('Host não configurado');
  return pair.baseUrl;
}

Future<NodeFileBytes> _read(
  WireClient client,
  Uri uri, {
  String? range,
  String? ifNoneMatch,
}) async {
  final res = await _raw(client, 'GET', uri, range: range, ifNoneMatch: ifNoneMatch);
  return NodeFileBytes(
    statusCode: res.statusCode,
    bytes: res.bytes,
    contentType: res.contentType,
    contentRange: res.contentRange,
    etag: res.etag,
  );
}

class _RawResponse {
  final int statusCode;
  final Uint8List bytes;
  final String? contentType;
  final String? contentRange;
  final String? etag;

  const _RawResponse(this.statusCode, this.bytes, this.contentType, this.contentRange, this.etag);
}

/// Requisição HTTP com TLS pinado e Bearer, igual ao `WireClient`, mas com corpo cru.
Future<_RawResponse> _raw(
  WireClient client,
  String method,
  Uri uri, {
  List<int>? body,
  String? contentType,
  String? range,
  String? ifNoneMatch,
}) async {
  final pair = client.currentPairData;
  if (pair == null) throw Exception('Host não configurado');
  final http = createPinnedHttpClient(expectedPin: pair.serverKeyHash);
  try {
    final request = await http.openUrl(method, uri);
    if (client.authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${client.authToken}');
    }
    request.headers.set(HttpHeaders.hostHeader, pair.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');
    if (contentType != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    if (ifNoneMatch != null) request.headers.set(HttpHeaders.ifNoneMatchHeader, ifNoneMatch);
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return _RawResponse(
      response.statusCode,
      builder.takeBytes(),
      response.headers.contentType?.toString(),
      response.headers.value(HttpHeaders.contentRangeHeader),
      response.headers.value(HttpHeaders.etagHeader),
    );
  } finally {
    http.close(force: true);
  }
}
