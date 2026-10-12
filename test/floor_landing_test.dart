import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/network/api_floors.dart';

void main() {
  group('FloorLanding', () {
    test('lê branches, arquivos e conflitos da prévia', () {
      final landing = FloorLanding.fromJson({
        'branch': 'feat/x',
        'groundBranch': 'main',
        'branches': ['main', 'feat/x', 'dev'],
        'target': 'main',
        'isMerge': true,
        'commitCount': 3,
        'files': [
          {'path': 'lib/a.dart', 'additions': 4, 'deletions': 1, 'isBinary': false},
          {'path': 'img.png', 'additions': 0, 'deletions': 0, 'isBinary': true},
        ],
        'conflicts': ['lib/b.dart'],
      });
      expect(landing.branch, 'feat/x');
      expect(landing.groundBranch, 'main');
      expect(landing.branches, ['main', 'feat/x', 'dev']);
      expect(landing.target, 'main');
      expect(landing.isMerge, isTrue);
      expect(landing.commitCount, 3);
      expect(landing.files.first.additions, 4);
      expect(landing.files.last.isBinary, isTrue);
      expect(landing.hasConflicts, isTrue);
      expect(landing.conflicts, ['lib/b.dart']);
    });

    test('campos ausentes ou malformados viram padrões seguros', () {
      final landing = FloorLanding.fromJson({
        'branches': 'não é lista',
        'files': [42, {'path': 'a.txt'}],
        'commitCount': 'x',
      });
      expect(landing.branches, isEmpty);
      expect(landing.commitCount, 0);
      expect(landing.files.map((f) => f.path), ['a.txt']);
      expect(landing.hasConflicts, isFalse);
      expect(landing.target, isNull);
    });
  });

  group('FloorApiException', () {
    test('lê código e mensagem do erro do host', () {
      final e = FloorApiException.fromResponse(
        409,
        '{"error": {"code": "conflict", "message": "Trabalho não commitado em lib/a.dart"}}',
      );
      expect(e.statusCode, 409);
      expect(e.code, 'conflict');
      expect(hostErrorText(e), 'Trabalho não commitado em lib/a.dart (HTTP 409)');
    });

    test('corpo que não é JSON vira a mensagem bruta', () {
      final e = FloorApiException.fromResponse(503, 'host indisponível');
      expect(e.code, 'http503');
      expect(e.message, 'host indisponível');
    });

    test('hostErrorText de outros erros remove o prefixo Exception', () {
      expect(hostErrorText(Exception('falhou')), 'falhou');
    });
  });
}
