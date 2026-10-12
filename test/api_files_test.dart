import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/network/api_files.dart';
import 'package:maestri_wire_client/core/network/wire_client.dart';

void main() {
  test('upload monta a query com filename, x, y, floor e mutationId', () {
    final uri = buildFileUploadUri(
      'https://h:7434',
      workspaceId: 'ws1',
      filename: 'nota teste.md',
      x: 120,
      y: 40.5,
      floorId: 'f1',
      mutationId: 'm1',
    );
    expect(uri.path, '/api/workspaces/ws1/files');
    expect(uri.queryParameters, {
      'filename': 'nota teste.md',
      'x': '120',
      'y': '40.5',
      'floor': 'f1',
      'mutationId': 'm1',
    });
  });

  test('parâmetros ausentes ficam fora da query', () {
    final uri = buildFileUploadUri('https://h:7434', workspaceId: 'ws1', filename: 'a.txt');
    expect(uri.queryParameters, {'filename': 'a.txt'});
  });

  test('upload acima de 8 MB é recusado antes de qualquer chamada', () async {
    final client = WireClient();
    final big = List<int>.filled(kMaxUploadBytes + 1, 0);
    expect(
      () => uploadWorkspaceFile(
        client: client,
        workspaceId: 'ws1',
        bytes: big,
        filename: 'grande.bin',
      ),
      throwsArgumentError,
    );
  });

  test('Content-Range dá o tamanho total do arquivo', () {
    final chunk = NodeFileBytes(
      statusCode: 206,
      bytes: Uint8List(0),
      contentRange: 'bytes 0-99/1234',
    );
    expect(chunk.totalLength, 1234);
    final none = NodeFileBytes(statusCode: 200, bytes: Uint8List(0));
    expect(none.totalLength, isNull);
  });
}
