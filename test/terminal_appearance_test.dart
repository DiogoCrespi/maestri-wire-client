import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/terminal_appearance.dart';

void main() {
  group('TerminalAppearance', () {
    test('lê o Appearance do host e usa padrões quando faltam campos', () {
      final a = TerminalAppearance.fromJson({'theme': 'custom', 'customThemeId': 'nord'});
      expect(a.theme, 'custom');
      expect(a.customThemeId, 'nord');
      expect(a.chatFont, 'system');
      expect(a.chatTextSize, 'system');
      expect(a.terminalFontSize, isNull);
      expect(a.startInChatMode, isFalse);
    });

    test('toJson limpa customThemeId fora de custom e terminalFontSize nulo', () {
      const a = TerminalAppearance(
        theme: 'dark',
        customThemeId: 'nord',
        terminalFontSize: 14,
      );
      final json = a.toJson(base: {'customThemeId': 'nord', 'terminalFontSize': 14});
      expect(json.containsKey('customThemeId'), isFalse);
      expect(json['terminalFontSize'], 14);

      final cleared = const TerminalAppearance(theme: 'system').toJson(
        base: {'terminalFontSize': 14, 'futuro': 'preservado'},
      );
      expect(cleared.containsKey('terminalFontSize'), isFalse);
      expect(cleared['futuro'], 'preservado');
    });

    test('toJson mantém darkThemeId do host', () {
      final json = TerminalAppearance.fromJson({
        'theme': 'light',
        'darkThemeId': 'nord',
      }).toJson();
      expect(json['darkThemeId'], 'nord');
    });

    test('copyWith troca só o campo pedido e aceita limpar', () {
      const a = TerminalAppearance(theme: 'custom', customThemeId: 'nord', terminalFontSize: 12);
      final b = a.copyWith(startInChatMode: true);
      expect(b.startInChatMode, isTrue);
      expect(b.customThemeId, 'nord');
      expect(b.terminalFontSize, 12);

      final c = a.copyWith(clearCustomThemeId: true, clearTerminalFontSize: true);
      expect(c.customThemeId, isNull);
      expect(c.terminalFontSize, isNull);
    });

    test('ThemeOption.listFromJson ignora lixo e entradas sem id', () {
      final themes = ThemeOption.listFromJson([
        {'id': 'nord', 'name': 'Nord', 'isLight': false},
        {'name': 'sem id'},
        'lixo',
      ]);
      expect(themes.length, 1);
      expect(themes.single.name, 'Nord');
      expect(ThemeOption.listFromJson(null), isEmpty);
    });

    test('isHexColor e hexColorToArgb exigem #RRGGBB', () {
      expect(isHexColor('#00FF7a'), isTrue);
      expect(isHexColor('#FFF'), isFalse);
      expect(isHexColor('00FF00'), isFalse);
      expect(hexColorToArgb('#00FF00'), 0xFF00FF00);
      expect(hexColorToArgb('nope'), isNull);
    });
  });
}
