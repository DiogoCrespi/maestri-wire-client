import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/network/terminal_text.dart';

/// Monta um frame de TUI em tela cheia no mesmo formato do Codex:
/// limpa a tela e posiciona cada linha com CUP (ESC[row;1H).
String tuiFrame(List<String> rows) {
  // TUIs como o Codex usam a tela alternativa (ESC[?1049h)
  final b = StringBuffer('\x1b[?1049h\x1b[H\x1b[2J');
  for (var i = 0; i < rows.length; i++) {
    b.write('\x1b[${i + 1};1H\x1b[2K${rows[i]}');
  }
  return b.toString();
}

void main() {
  group('UTF-8 com estado', () {
    test('caractere acentuado cortado entre dois frames não vira U+FFFD', () {
      final bytes = utf8.encode('› atualização\r\n');
      final cut = bytes.indexOf(0xC3) + 1; // corta o meio do 'ç'

      final conv = TerminalConversation()
        ..addBytes(bytes.sublist(0, cut))
        ..addBytes(bytes.sublist(cut));

      expect(conv.blocks.single.text, 'atualização');
      expect(conv.plainText, isNot(contains('�')));
    });

    test('um byte por frame preserva todos os acentos', () {
      const sample = 'áãàâäåæª@#\$_&-+()';
      final conv = TerminalConversation();
      for (final b in utf8.encode('› $sample\r\n')) {
        conv.addBytes([b]);
      }
      expect(conv.blocks.single.text, sample);
    });
  });

  group('emulador de tela', () {
    test('CUP posiciona o texto na linha certa', () {
      final screen = TerminalScreen(rows: 5, cols: 20)
        ..write('\x1b[2;1Hhello');
      expect(screen.screenLines[1], 'hello');
      expect(screen.screenLines[0], '');
    });

    test('\\r sobrescreve a linha (spinner não vira várias linhas)', () {
      final screen = TerminalScreen(rows: 5, cols: 60)
        ..write('• Working (1s • esc to interrupt)\r')
        ..write('• Working (2s • esc to interrupt)\r')
        ..write('• Working (3s • esc to interrupt)');
      expect(screen.screenLines[0], '• Working (3s • esc to interrupt)');
    });

    test('ESC[K apaga do cursor até o fim da linha', () {
      final screen = TerminalScreen(rows: 2, cols: 20)
        ..write('hello\rhi\x1b[K');
      expect(screen.screenLines[0], 'hi');
    });

    test('linha que rola para fora da tela vai para o scrollback', () {
      final screen = TerminalScreen(rows: 2, cols: 20)
        ..write('um\r\ndois\r\ntres');
      expect(screen.scrollback, ['um']);
      expect(screen.screenLines, ['dois', 'tres']);
    });

    test('sequência cortada entre frames é reconhecida', () {
      final screen = TerminalScreen(rows: 2, cols: 20)
        ..write('\x1b[')
        ..write('2;1H')
        ..write('ok');
      expect(screen.screenLines[1], 'ok');
    });

    test('OSC é descartado inteiro', () {
      final screen = TerminalScreen(rows: 2, cols: 20)
        ..write('\x1b]0;título\x07ok');
      expect(screen.screenLines[0], 'ok');
    });
  });

  group('conversa', () {
    test('separa usuário, resposta final e status "Worked for"', () {
      final conv = TerminalConversation(rows: 10, cols: 80)
        ..addBytes(utf8.encode(tuiFrame([
          '› opa tá chegando?',
          '• Sim, chegou.',
          '  Worked for 1s • 4:48 PM',
        ])));

      expect(conv.blocks.map((b) => b.kind).toList(), [
        TerminalBlockKind.user,
        TerminalBlockKind.agent,
        TerminalBlockKind.status,
      ]);
      expect(conv.blocks[1].text, 'Sim, chegou.');
    });

    test('resposta final continua aparecendo depois de o TUI redesenhar', () {
      final conv = TerminalConversation(rows: 10, cols: 80)
        ..addText(tuiFrame(['› teste', '• Working (1s • esc to interrupt)']))
        ..addText(tuiFrame(['› teste', '• Recebi o teste.', '  Worked for 2s • 4:48 PM']))
        ..addText(tuiFrame(['› teste', '• Recebi o teste.', '  Worked for 2s • 4:48 PM']));

      final kinds = conv.blocks.map((b) => b.kind).toList();
      expect(kinds, [
        TerminalBlockKind.user,
        TerminalBlockKind.agent,
        TerminalBlockKind.status,
      ]);
      expect(conv.blocks[1].text, 'Recebi o teste.');
    });

    test('"• Working (…)" é status transitório, não resposta', () {
      final conv = TerminalConversation(rows: 10, cols: 80)
        ..addText(tuiFrame(['› oi', '• Working (3s • esc to interrupt)']));

      expect(conv.blocks.map((b) => b.kind).toList(), [
        TerminalBlockKind.user,
        TerminalBlockKind.status,
      ]);
      expect(conv.blocks.last.text, 'Working (3s • esc to interrupt)');
    });

    test('resposta que cresce durante o streaming substitui a anterior', () {
      final conv = TerminalConversation(rows: 10, cols: 80)
        ..addText(tuiFrame(['• Recebi']))
        ..addText(tuiFrame(['• Recebi o teste.']));

      expect(conv.blocks.single.text, 'Recebi o teste.');
    });

    test('cabeçalho e rodapé da TUI não viram mensagem', () {
      final conv = TerminalConversation(rows: 10, cols: 100)
        ..addText(tuiFrame([
          '› oi',
          '• Oi! Estou recebendo suas mensagens.',
          'Worked for 1s • 7:29 PM',
          '› Ask Codex to do anything',
          'GPT-6-Luna default · /home/debian/Documentos · Analise',
          '← for agents · ? for shortcuts',
        ]));

      expect(conv.blocks.map((b) => b.kind).toList(), [
        TerminalBlockKind.user,
        TerminalBlockKind.agent,
        TerminalBlockKind.status,
      ]);
    });

    test('mensagem enviada pelo app não duplica quando a TUI a mostra', () {
      final conv = TerminalConversation(rows: 10, cols: 80)
        ..addUserMessage('teste')
        ..addText(tuiFrame(['› teste', '• Recebi o teste.']));

      expect(conv.blocks.where((b) => b.kind == TerminalBlockKind.user).length, 1);
    });

    test('histórico sobrevive quando a TUI rola o conteúdo para fora', () {
      final conv = TerminalConversation(rows: 4, cols: 80)
        ..addText(tuiFrame(['› primeira', '• resposta um']))
        ..addText(tuiFrame(['› segunda', '• resposta dois']));

      expect(conv.blocks.map((b) => b.text).toList(),
          containsAllInOrder(['primeira', 'resposta um']));
      expect(conv.blocks.map((b) => b.text), contains('segunda'));
    });
  });

  group('agrupamento em blocos', () {
    test('linhas sem prefixo continuam a resposta do agente', () {
      final blocks = groupTerminalBlocks([
        '• Recebi o teste',
        '  segunda linha',
      ]);
      expect(blocks.single.kind, TerminalBlockKind.agent);
      expect(blocks.single.text, 'Recebi o teste\n  segunda linha');
    });

    test('"Worked for" e "Brewed for" (✻) são status', () {
      expect(groupTerminalBlocks(['Worked for 5s']).single.kind,
          TerminalBlockKind.status);
      expect(groupTerminalBlocks(['✻ Brewed for 35s · done 7:42']).single.kind,
          TerminalBlockKind.status);
    });
  });

  group('saída de shell x TUI', () {
    test('shell (tela normal) vira conversa crua, sem precisar de TUI', () {
      final conv = TerminalConversation(rows: 10, cols: 80)
        ..addText('debian@DCX:~/Documentos\$ agy\r\n')
        ..addText('bash: agy: comando não encontrado\r\n')
        ..addText('debian@DCX:~/Documentos\$ ');
      final texts = conv.blocks.map((b) => b.text).join('\n');
      expect(conv.blocks, isNotEmpty);
      expect(texts, contains('comando não encontrado'));
    });

    test('TUI em tela alternativa não polui a conversa com linhas de tela', () {
      final conv = TerminalConversation(rows: 10, cols: 80)
        ..addText('\x1b[?1049h')
        ..addText(tuiFrame(['linha solta de chrome do TUI']));
      expect(conv.screen.alternate, isTrue);
      expect(conv.blocks.where((b) => b.kind == TerminalBlockKind.raw), isEmpty);
    });
  });

  group('ruído do Claude Code', () {
    test('spinner com tokens, dicas e barra de modo não viram conversa', () {
      final conv = TerminalConversation(rows: 12, cols: 80)
        ..addText(tuiFrame([
          '❯ oi',
          '● Oi, tudo bem?',
          '✻ Slithering… (2s · ↓ 116 tokens)',
          '  ⎿ Tip: See an artifact you\'d like to build on?',
          '❯ ',
          '▸▸ auto mode on (shift+tab to cycle)',
        ]));
      final texts = conv.blocks.map((b) => b.text).toList();
      expect(texts, ['oi', 'Oi, tudo bem?']);
    });

    test('a mesma resposta redesenhada várias vezes aparece uma vez só', () {
      final conv = TerminalConversation(rows: 12, cols: 80);
      for (var i = 0; i < 3; i++) {
        conv.addText(tuiFrame(['● Recebi o teste.', '✻ Thinking… (${i}s · 9 tokens)']));
      }
      expect(conv.blocks.where((b) => b.text == 'Recebi o teste.').length, 1);
    });
  });
}
