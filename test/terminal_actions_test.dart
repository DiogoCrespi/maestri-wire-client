import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/terminal_settings.dart';

void main() {
  Map<String, dynamic> getBody() => {
        'command': 'claude --resume',
        'workingDirectory': '/home/debian/Documentos',
        'roles': [
          {'id': 'R1', 'name': 'Revisor', 'icon': 'eye', 'color': '#FF0000'},
        ],
        'roleId': 'R1',
        'maestroMode': false,
        'icon': 'seal',
        'color': '#007AFF',
        'monitorActivity': true,
        'appearance': {
          'theme': 'dark',
          'darkThemeId': 'nord',
          'chatFont': 'system',
          'chatTextSize': 'system',
          'startInChatMode': false,
        },
        'themes': [
          {'id': 'nord', 'name': 'Nord', 'isLight': false},
        ],
      };

  group('TerminalSettings.fromJson', () {
    test('lê o GET de configurações do host', () {
      final s = TerminalSettings.fromJson(getBody());
      expect(s.command, 'claude --resume');
      expect(s.workingDirectory, '/home/debian/Documentos');
      expect(s.roleId, 'R1');
      expect(s.maestroMode, isFalse);
      expect(s.icon, 'seal');
      expect(s.color, '#007AFF');
      expect(s.monitorActivity, isTrue);
      expect(s.appearance?['theme'], 'dark');
    });

    test('campos ausentes ou vazios viram null/padrão', () {
      final s = TerminalSettings.fromJson({
        'command': '',
        'roleId': '',
        'icon': '',
      });
      expect(s.command, '');
      expect(s.roleId, isNull);
      expect(s.icon, isNull);
      expect(s.color, isNull);
      expect(s.maestroMode, isFalse);
      expect(s.monitorActivity, isFalse);
      expect(s.appearance, isNull);
    });
  });

  group('TerminalSettings.toPutBody (substituição completa)', () {
    test('troca só maestroMode e preserva command/icon/color/monitorActivity', () {
      final s = TerminalSettings.fromJson(getBody());
      final body = s.toPutBody(maestroMode: true);

      expect(body['maestroMode'], isTrue);
      expect(body['command'], 'claude --resume');
      expect(body['icon'], 'seal');
      expect(body['color'], '#007AFF');
      expect(body['monitorActivity'], isTrue);
      expect(body['roleId'], 'R1');
      expect(body['appearance'], s.appearance);
    });

    test('não envia campos que só existem no GET (roles, themes, workingDirectory)', () {
      final body = TerminalSettings.fromJson(getBody()).toPutBody();
      expect(body.containsKey('roles'), isFalse);
      expect(body.containsKey('themes'), isFalse);
      expect(body.containsKey('workingDirectory'), isFalse);
    });

    test('sem overrides devolve o estado atual', () {
      final body = TerminalSettings.fromJson(getBody()).toPutBody();
      expect(body['maestroMode'], isFalse);
      expect(body['monitorActivity'], isTrue);
    });

    test('monitorActivity pode ser trocado sem tocar no resto', () {
      final body = TerminalSettings.fromJson(getBody()).toPutBody(monitorActivity: false);
      expect(body['monitorActivity'], isFalse);
      expect(body['maestroMode'], isFalse);
      expect(body['command'], 'claude --resume');
    });

    test('sem icon/color/roleId no GET, o corpo também não os inventa', () {
      final s = TerminalSettings.fromJson({'command': 'zsh', 'maestroMode': true});
      final body = s.toPutBody();
      expect(body, {
        'command': 'zsh',
        'maestroMode': true,
        'monitorActivity': false,
      });
    });

    test('override de icon e color prevalece sobre o GET', () {
      final body = TerminalSettings.fromJson(getBody()).toPutBody(icon: 'brain', color: '#00FF00');
      expect(body['icon'], 'brain');
      expect(body['color'], '#00FF00');
      expect(body['maestroMode'], isFalse);
    });
  });

  group('TerminalSettings: roles, themes e aparência', () {
    test('lê roles e themes do GET', () {
      final s = TerminalSettings.fromJson(getBody());
      expect(s.roles.single.name, 'Revisor');
      expect(s.themes.single.id, 'nord');
      expect(s.appearanceModel?.darkThemeId, 'nord');
    });

    test('PUT leva a aparência nova e preserva o que o host mandou', () {
      final s = TerminalSettings.fromJson(getBody());
      final body = s.toPutBody(
        appearance: s.appearanceModel!.copyWith(startInChatMode: true),
      );
      final app = body['appearance'] as Map<String, dynamic>;
      expect(app['startInChatMode'], isTrue);
      expect(app['darkThemeId'], 'nord');
      expect(app['theme'], 'dark');
    });

    test('clearRole, clearIcon e clearColor apagam os campos', () {
      final body = TerminalSettings.fromJson(getBody()).toPutBody(
        clearRole: true,
        clearIcon: true,
        clearColor: true,
      );
      expect(body.containsKey('roleId'), isFalse);
      expect(body.containsKey('icon'), isFalse);
      expect(body.containsKey('color'), isFalse);
      expect(body['command'], 'claude --resume');
    });

    test('command substitui o atual quando informado', () {
      final body = TerminalSettings.fromJson(getBody()).toPutBody(command: 'zsh');
      expect(body['command'], 'zsh');
    });

    test('sem appearance no GET, o PUT não inventa o campo', () {
      final body = TerminalSettings.fromJson({'command': 'zsh'}).toPutBody();
      expect(body.containsKey('appearance'), isFalse);
      expect(TerminalSettings.fromJson({'command': 'zsh'}).appearanceModel, isNull);
    });
  });
}
