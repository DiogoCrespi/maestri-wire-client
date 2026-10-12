import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/network/api_partituras.dart';
import 'package:maestri_wire_client/models/partitura.dart';

void main() {
  group('Partitura', () {
    test('lê uma partitura de GET /api/partituras', () {
      final p = Partitura.fromJson({
        'id': 'p1',
        'name': 'Arranjo',
        'summary': 'Dois terminais',
        'icon': 'music',
        'color': '#1633F9',
        'workspaceId': 'ws1',
        'roles': [
          {'id': 'r1', 'name': 'Revisor', 'icon': 'eye', 'color': '#FF0000'},
        ],
      });
      expect(p.workspaceId, 'ws1');
      expect(p.roles.single.name, 'Revisor');
    });

    test(
        'workspaceId ausente ou vazio vira null, roles ausentes vira lista vazia',
        () {
      final p =
          Partitura.fromJson({'id': 'p2', 'name': 'Solta', 'workspaceId': ''});
      expect(p.workspaceId, isNull);
      expect(p.roles, isEmpty);
    });

    test('listFromJson lê {partituras: [...]} e descarta sem id', () {
      final list = Partitura.listFromJson({
        'partituras': [
          {'id': 'p1', 'name': 'A'},
          {'name': 'sem id'},
        ],
      });
      expect(list.map((p) => p.id), ['p1']);
      expect(Partitura.listFromJson({'partituras': 'x'}), isEmpty);
    });
  });

  group('caminhos de partitura', () {
    test('preview e id são codificados', () {
      expect(partituraPath('p1', 'preview'), '/api/partituras/p1/preview');
      expect(partituraPath('a/b'), '/api/partituras/a%2Fb');
    });
  });
}
