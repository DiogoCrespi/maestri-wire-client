import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/agent_role.dart';

void main() {
  group('AgentRole', () {
    test('lê a Role devolvida por GET /api/roles', () {
      final role = AgentRole.fromJson({
        'id': 'r1',
        'name': 'Revisor',
        'prompt': 'revise o código',
        'icon': 'sparkles',
        'color': '#AF52DE',
        'terminalsInUse': 2,
      });
      expect(role.id, 'r1');
      expect(role.name, 'Revisor');
      expect(role.terminalsInUse, 2);
      expect(role.workspaceId, isNull, reason: 'ausente significa global');
    });

    test('workspaceId vazio vira global', () {
      final role = AgentRole.fromJson({
        'id': 'r2',
        'name': 'x',
        'prompt': 'y',
        'icon': 'a',
        'color': '#000000',
        'workspaceId': '',
      });
      expect(role.workspaceId, isNull);
    });

    test('toWrite reenvia workspaceId para não apagar o escopo no PUT', () {
      final role = AgentRole.fromJson({
        'id': 'r3',
        'name': 'Local',
        'prompt': 'p',
        'icon': 'sparkles',
        'color': '#112233',
        'workspaceId': '09a7826f-6c8c-42de-9e07-a41996df929f',
      });
      expect(role.toWrite().toJson(), {
        'name': 'Local',
        'prompt': 'p',
        'icon': 'sparkles',
        'color': '#112233',
        'workspaceId': '09a7826f-6c8c-42de-9e07-a41996df929f',
      });
    });

    test('RoleWrite global omite workspaceId', () {
      const write = RoleWrite(name: 'n', prompt: 'p', icon: 'i', color: '#FFFFFF');
      expect(write.toJson().containsKey('workspaceId'), isFalse);
    });
  });

  group('TerminalSettings', () {
    final json = {
      'command': 'claude',
      'workingDirectory': '/home/debian/Documentos',
      'roleId': 'r1',
      'roles': [
        {'id': 'r1', 'name': 'Revisor', 'icon': 'sparkles', 'color': '#AF52DE'},
      ],
      'maestroMode': false,
      'icon': 'terminal',
      'color': '#00FF00',
      'monitorActivity': true,
      'appearance': {'theme': 'dark', 'chatFont': 'system', 'chatTextSize': 'medium', 'startInChatMode': false},
      'themes': [],
    };

    test('lê as configurações do terminal', () {
      final s = TerminalSettings.fromJson(json);
      expect(s.roleId, 'r1');
      expect(s.roles.single.name, 'Revisor');
      expect(s.maestroMode, isFalse);
      expect(s.monitorActivity, isTrue);
    });

    test('roleId ausente ou vazio vira null', () {
      final s = TerminalSettings.fromJson({...json, 'roleId': null});
      expect(s.roleId, isNull);
    });

    test('toPutBody troca só a responsabilidade e mantém os demais campos', () {
      final body = TerminalSettings.fromJson(json).toPutBody(roleId: 'r9');
      expect(body, {
        'command': 'claude',
        'roleId': 'r9',
        'maestroMode': false,
        'icon': 'terminal',
        'color': '#00FF00',
        'monitorActivity': true,
        'appearance': json['appearance'],
      });
      expect(body.containsKey('workingDirectory'), isFalse);
      expect(body.containsKey('roles'), isFalse);
    });

    test('toPutBody com roleId null remove a responsabilidade', () {
      final body = TerminalSettings.fromJson(json).toPutBody(roleId: null);
      expect(body.containsKey('roleId'), isFalse);
    });
  });
}
