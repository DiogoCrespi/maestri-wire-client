import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/agent_preset.dart';

void main() {
  group('AgentPreset', () {
    test('lê um preset de GET /api/agent-presets', () {
      final p = AgentPreset.fromJson({
        'id': 'C1A0DE00-0000-4000-8000-000000000003',
        'name': 'Antigravity',
        'agentType': 'antigravity_cli',
        'icon': 'sparkle',
        'isManager': false,
        'isDefault': false,
        'command': 'agy',
        'appearance': {'theme': 'system'},
      });
      expect(p.agentType, 'antigravity_cli');
      expect(p.command, 'agy');
      expect(p.isDefault, isFalse);
    });

    test('Shell sem comando vira command nulo', () {
      final p = AgentPreset.fromJson({
        'id': 'x',
        'name': 'Shell',
        'agentType': 'generic_shell',
        'icon': 'terminal',
        'command': '',
      });
      expect(p.command, isNull);
    });

    test('campos ausentes têm padrão seguro', () {
      final p = AgentPreset.fromJson({'id': 'y'});
      expect(p.name, '');
      expect(p.isManager, isFalse);
      expect(p.command, isNull);
    });

    test('listFromJson ignora entradas inválidas e sem id', () {
      final list = AgentPreset.listFromJson({
        'presets': [
          {'id': 'a', 'name': 'Claude Code', 'agentType': 'claude_code', 'isDefault': true},
          {'name': 'sem id'},
          'lixo',
        ],
        'themes': [],
      });
      expect(list.length, 1);
      expect(list.single.isDefault, isTrue);
    });

    test('listFromJson sem presets devolve lista vazia', () {
      expect(AgentPreset.listFromJson({}), isEmpty);
    });
  });

  group('AgentPreset com aparência e catálogo', () {
    test('lê appearance, color e startInChatMode do preset', () {
      final p = AgentPreset.fromJson({
        'id': 'a',
        'name': 'Codex',
        'color': '#AF52DE',
        'appearance': {'theme': 'dark', 'startInChatMode': true},
      });
      expect(p.color, '#AF52DE');
      expect(p.appearance?.theme, 'dark');
      expect(p.startInChatMode, isTrue);
    });

    test('preset sem appearance tem startInChatMode falso', () {
      final p = AgentPreset.fromJson({'id': 'b'});
      expect(p.appearance, isNull);
      expect(p.startInChatMode, isFalse);
      expect(p.color, isNull);
    });

    test('catálogo traz presets, temas e aparência padrão', () {
      final c = AgentPresetCatalog.fromJson({
        'presets': [
          {'id': 'a', 'name': 'Claude Code', 'isDefault': true},
        ],
        'themes': [
          {'id': 'nord', 'name': 'Nord', 'isLight': false},
        ],
        'defaultAppearance': {'theme': 'system', 'startInChatMode': false},
      });
      expect(c.presets.single.name, 'Claude Code');
      expect(c.themes.single.id, 'nord');
      expect(c.supportsAppearance, isTrue);
    });

    test('host antigo sem defaultAppearance esconde os controles de aparência', () {
      final c = AgentPresetCatalog.fromJson({
        'presets': [
          {'id': 'a', 'name': 'Shell'},
        ],
      });
      expect(c.supportsAppearance, isFalse);
      expect(c.themes, isEmpty);
    });
  });
}
