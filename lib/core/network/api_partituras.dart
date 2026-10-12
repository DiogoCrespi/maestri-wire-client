import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../models/partitura.dart';
import 'tls_pinning.dart';
import 'wire_client.dart';

/// Resultado de uma prévia JPEG. `bytes` null significa 304: a imagem anterior serve.
class PartituraPreview {
  final Uint8List? bytes;
  final String? etag;

  const PartituraPreview({this.bytes, this.etag});
}

/// Biblioteca de partituras do host. Capability `partituras`.
/// Contrato: "## Partituras" em notes/maestri-wire.md. Só leitura e estampar.
extension PartiturasApi on WireClient {
  /// `GET /api/partituras`
  Future<List<Partitura>> listPartituras() async {
    final json = await getJson('/api/partituras');
    return Partitura.listFromJson(json);
  }

  /// `GET /api/partituras/{id}/preview?appearance=light|dark`: JPEG com ETag.
  /// Com [etag] igual ao atual, o host responde 304 e `bytes` vem null.
  Future<PartituraPreview> fetchPartituraPreview(
    String id, {
    String appearance = 'light',
    String? etag,
  }) async {
    final pair = currentPairData;
    if (pair == null) throw Exception('Host não configurado');
    final http = createPinnedHttpClient(expectedPin: pair.serverKeyHash)
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(
        '${pair.baseUrl}${partituraPath(id, 'preview')}?appearance=${Uri.encodeQueryComponent(appearance)}',
      );
      final request = await http.getUrl(uri);
      if (authToken != null) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
      }
      request.headers.set(HttpHeaders.hostHeader, pair.host);
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      if (etag != null) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }

      final response = await request.close();
      if (response.statusCode == 304) {
        await response.drain<void>();
        return PartituraPreview(etag: etag);
      }
      if (response.statusCode != 200) {
        final text = await response.transform(utf8.decoder).join();
        throw HttpException(
            'Prévia respondeu HTTP ${response.statusCode}${text.isEmpty ? '' : ': $text'}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return PartituraPreview(
        bytes: builder.takeBytes(),
        etag: response.headers.value(HttpHeaders.etagHeader),
      );
    } finally {
      http.close(force: true);
    }
  }

  /// `POST /api/workspaces/{ws}/partituras`: estampa a partitura centrada em x,y.
  /// Não é chamada pelas telas de leitura; o botão Estampar só a usa quando a
  /// pessoa confirma. [mutationId] torna a requisição idempotente.
  Future<void> stampPartitura({
    required String workspaceId,
    required String partituraId,
    required double x,
    required double y,
    String? floorId,
    String? mutationId,
  }) async {
    final body = <String, dynamic>{
      'partituraId': partituraId,
      'x': x,
      'y': y,
      'mutationId': mutationId ?? const Uuid().v4(),
    };
    if (floorId != null) body['floorId'] = floorId;
    final response = await sendJson(
      'POST',
      '/api/workspaces/${Uri.encodeComponent(workspaceId)}/partituras',
      body,
    );
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
          'Estampar respondeu HTTP ${response.statusCode}${text.isEmpty ? '' : ': $text'}');
    }
  }
}

/// Caminho `/api/partituras/{id}[/suffix]`.
String partituraPath(String id, [String? suffix]) {
  final base = '/api/partituras/${Uri.encodeComponent(id)}';
  return suffix == null ? base : '$base/$suffix';
}
