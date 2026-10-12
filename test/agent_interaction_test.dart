import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/terminal/agent_interaction.dart';

void main() {
  group('perguntas de escolha', () {
    test('lista numerada com a opção selecionada', () {
      final p = detectChoicePrompt([
        'Deseja aplicar a mudança?',
        '❯ 1. Sim, aplicar',
        '  2. Não, cancelar',
        '  3. Explicar antes',
      ]);
      expect(p, isNotNull);
      expect(p!.question, 'Deseja aplicar a mudança?');
      expect(p.options.map((o) => o.key), ['1', '2', '3']);
      expect(p.options.first.isSelected, isTrue);
      expect(p.options[1].isSelected, isFalse);
      expect(p.options[1].label, 'Não, cancelar');
    });

    test('opções inline numa linha só', () {
      final p = detectChoicePrompt(['Qual é a sua cor favorita?', '1. Azul 2. Verde 3. Vermelho']);
      expect(p, isNotNull);
      expect(p!.question, 'Qual é a sua cor favorita?');
      expect(p.options.map((o) => o.label), ['Azul', 'Verde', 'Vermelho']);
    });

    test('opções seguidas de linha de status e espaço em branco', () {
      final p = detectChoicePrompt([
        'Qual é a sua cor favorita?',
        '1. Azul 2. Verde 3. Vermelho',
        '',
        '✻ Sautéed for 1s · done 22:15',
        '',
      ]);
      expect(p, isNotNull);
      expect(p!.options.length, 3);
      expect(p.question, 'Qual é a sua cor favorita?');
    });

    test('menu do Claude: descrições entre as opções e rodapé de navegação', () {
      final p = detectChoicePrompt([
        'Qual é a sua cor favorita?',
        '❯ 1. Azul',
        '     Cor azul',
        '  2. Verde',
        '     Cor verde',
        '  3. Vermelho',
        '  4. Type something.',
        '  5. Chat about this',
        'Enter to select · ↑/↓ to navigate · Esc to cancel',
      ]);
      expect(p, isNotNull);
      expect(p!.options.map((o) => o.label), ['Azul', 'Verde', 'Vermelho', 'Type something.', 'Chat about this']);
      expect(p.options.first.isSelected, isTrue);
      expect(p.question, 'Qual é a sua cor favorita?');
    });

    test('sim/não com (y/n)', () {
      final p = detectChoicePrompt(['Rodar o comando rm? (y/n)']);
      expect(p, isNotNull);
      expect(p!.options.map((o) => o.key), ['y', 'n']);
    });

    test('texto comum não vira pergunta', () {
      expect(detectChoicePrompt(['Oi, tudo bem?', 'Fiz a mudança.']), isNull);
    });

    test('um único item numerado não é escolha', () {
      expect(detectChoicePrompt(['1. só uma coisa']), isNull);
    });
  });

  group('atalhos /', () {
    test('filtra comandos do agente pelo prefixo', () {
      expect(slashSuggestions('codex', '/mo'), ['/model']);
      expect(slashSuggestions('claude_code', '/co'), containsAll(['/compact', '/config', '/cost']));
    });

    test('sem barra ou shell não sugere nada', () {
      expect(slashSuggestions('codex', 'oi'), isEmpty);
      expect(slashSuggestions('generic_shell', '/'), isEmpty);
    });
  });

  group('seleção em menu', () {
    final menu = ChoicePrompt(question: 'cor?', options: const [
      ChoiceOption(key: '1', label: 'Azul', isSelected: true),
      ChoiceOption(key: '2', label: 'Verde'),
      ChoiceOption(key: '3', label: 'Vermelho'),
    ]);

    test('opção marcada: só Enter', () {
      expect(choiceKeySequence(menu, menu.options[0]), '\r');
    });

    test('opção abaixo: seta para baixo até ela e Enter', () {
      expect(choiceKeySequence(menu, menu.options[2]), '\x1b[B\x1b[B\r');
    });

    test('y/n responde com a letra', () {
      const yn = ChoicePrompt(question: 'rodar?', options: [
        ChoiceOption(key: 'y', label: 'Sim'),
        ChoiceOption(key: 'n', label: 'Não'),
      ]);
      expect(choiceKeySequence(yn, yn.options[1]), 'n\r');
    });
  });
}
