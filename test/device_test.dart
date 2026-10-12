import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/device.dart';

void main() {
  group('PairedDevice', () {
    test('lê um item de GET /api/devices', () {
      final d = PairedDevice.fromJson({
        'id': '6516AF12-B576-467C-9DC7-03CDD111159D',
        'name': 'debug-claude',
        'lastSeenIP': '100.111.3.16',
        'lastSeenAt': '2026-10-12T01:33:55Z',
        'createdAt': '2026-10-11T22:30:39Z',
        'role': 'owner',
      });
      expect(d.name, 'debug-claude');
      expect(d.isOwner, isTrue);
      expect(d.isGuest, isFalse);
      expect(d.lastSeenIP, '100.111.3.16');
      expect(d.lastSeenAt, DateTime.utc(2026, 10, 12, 1, 33, 55));
    });

    test('papel ausente ou desconhecido vira null', () {
      expect(
          PairedDevice.fromJson({'id': 'a', 'name': 'x', 'role': 'admin'}).role,
          isNull);
      expect(PairedDevice.fromJson({'id': 'a', 'name': 'x'}).role, isNull);
    });

    test('guest e datas inválidas', () {
      final d = PairedDevice.fromJson({
        'id': 'a',
        'name': 'Painel',
        'role': 'guest',
        'lastSeenAt': 'não é data',
        'lastSeenIP': '   ',
      });
      expect(d.isGuest, isTrue);
      expect(d.lastSeenAt, isNull);
      expect(d.lastSeenIP, isNull);
    });

    test('listFromJson ignora entradas sem id e corpo inválido', () {
      final list = PairedDevice.listFromJson({
        'devices': [
          {'id': 'a', 'name': 'A', 'role': 'owner'},
          {'name': 'sem id'},
          'lixo',
        ],
      });
      expect(list.map((d) => d.id), ['a']);
      expect(PairedDevice.listFromJson({}), isEmpty);
    });
  });

  group('normalizeDeviceName', () {
    test('apara espaços', () {
      expect(normalizeDeviceName('  Ponte micro  '), 'Ponte micro');
    });

    test('rejeita vazio e acima de 80 caracteres', () {
      expect(() => normalizeDeviceName('   '), throwsArgumentError);
      expect(() => normalizeDeviceName('a' * 81), throwsArgumentError);
      expect(normalizeDeviceName('a' * 80), 'a' * 80);
    });
  });
}
