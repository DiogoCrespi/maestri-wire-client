import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/floor_hooks.dart';

void main() {
  group('FloorHooksSnapshot', () {
    final json = {
      'hooks': {
        'isEnabled': true,
        'autoRunSetup': false,
        'setup': [
          {'id': 'c1', 'command': 'npm i', 'isEnabled': true},
          {'id': 'c2', 'command': 'pode ignorar', 'isEnabled': false},
          'entrada inválida',
        ],
        'run': [
          {'id': 'c3', 'command': 'npm start'},
        ],
        'teardown': 'não é lista',
      },
      'runs': [
        {'commandId': 'c1', 'floorId': 'f1', 'isRunning': false, 'exitCode': 0},
        {'commandId': 'c3', 'isRunning': true},
        {'commandId': 'c3', 'isRunning': false, 'exitCode': 2},
      ],
    };

    test('lê comandos, ignora entradas inválidas e aceita seções ausentes', () {
      final snap = FloorHooksSnapshot.fromJson(json);
      expect(snap.hooks.isEnabled, isTrue);
      expect(snap.hooks.autoRunSetup, isFalse);
      expect(snap.hooks.setup.map((c) => c.id), ['c1', 'c2']);
      expect(snap.hooks.setup.last.isEnabled, isFalse);
      expect(snap.hooks.run.single.isEnabled, isTrue, reason: 'isEnabled ausente vale true');
      expect(snap.hooks.teardown, isEmpty);
    });

    test('runFor devolve a execução mais recente do comando', () {
      final snap = FloorHooksSnapshot.fromJson(json);
      expect(snap.runFor('c3')!.exitCode, 2);
      expect(snap.runFor('c1')!.floorId, 'f1');
      expect(snap.runFor('nada'), isNull);
    });
  });

  group('FloorHooks.toJson (corpo do PUT)', () {
    test('formato hooks sem envelope, com os ids mantidos', () {
      final hooks = FloorHooks(
        isEnabled: true,
        autoRunSetup: true,
        setup: const [HookCommand(id: 'c1', command: 'npm i')],
      ).withSection('run', const [HookCommand(id: 'c9', command: 'make', isEnabled: false)]);
      expect(hooks.toJson(), {
        'isEnabled': true,
        'autoRunSetup': true,
        'setup': [
          {'id': 'c1', 'command': 'npm i', 'isEnabled': true},
        ],
        'run': [
          {'id': 'c9', 'command': 'make', 'isEnabled': false},
        ],
        'teardown': <Map<String, dynamic>>[],
      });
    });

    test('round trip preserva os comandos', () {
      final json = FloorHooks(setup: const [HookCommand(id: 'a', command: 'x')]).toJson();
      final back = FloorHooks.fromJson(json);
      expect(back.setup.single.command, 'x');
      expect(back.setup.single.id, 'a');
    });

    test('novo comando recebe um id único', () {
      expect(HookCommand.newId(), isNot(HookCommand.newId()));
    });
  });
}
