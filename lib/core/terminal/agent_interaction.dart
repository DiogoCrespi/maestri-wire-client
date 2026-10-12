/// Interações que um agente pede ao usuário no terminal: perguntas de escolha
/// (lista numerada ou sim/não) e atalhos de barra (`/comando`).

class ChoiceOption {
  /// Tecla que seleciona a opção (ex.: "1", "y").
  final String key;
  final String label;
  final bool isSelected;

  const ChoiceOption({required this.key, required this.label, this.isSelected = false});
}

class ChoicePrompt {
  final String question;
  final List<ChoiceOption> options;

  const ChoicePrompt({required this.question, required this.options});
}

final _numbered = RegExp(r'^\s*(❯|›|>)?\s*(\d{1,2})[.)]\s+(.+?)\s*$');
final _inlineNumbered = RegExp(r'(\d{1,2})\.\s+(.+?)(?=\s+\d{1,2}\.\s|\s*$)');
final _yesNo = RegExp(r'\((y/n|Y/n|y/N)\)|\[(y/n|Y/n|y/N)\]', caseSensitive: false);

/// Procura, nas linhas mais recentes, uma pergunta com opções. Retorna null se não há.
ChoicePrompt? detectChoicePrompt(List<String> lines, {int window = 12}) {
  // Só linhas não vazias: a tela tem espaço em branco no fim, e a linha de status
  // (ex.: "Sautéed for 1s") pode vir logo depois das opções.
  final nonEmpty = [for (final l in lines) if (l.trim().isNotEmpty) l];
  final recent = nonEmpty.length > window ? nonEmpty.sublist(nonEmpty.length - window) : nonEmpty;

  // 1) Menu numerado: itens "1. …", "2. …" em sequência, mesmo com descrições
  //    entre eles e um rodapé ("Enter to select · ↑/↓ to navigate"). A marcada com ❯ é a selecionada.
  final numbered = <int, ({String key, String label, bool sel, int at})>{};
  for (var k = 0; k < recent.length; k++) {
    final m = _numbered.firstMatch(recent[k]);
    if (m == null) continue;
    final n = int.parse(m.group(2)!);
    numbered[n] = (key: m.group(2)!, label: m.group(3)!, sel: (m.group(1) ?? '').isNotEmpty, at: k);
  }
  if (numbered.containsKey(1)) {
    final options = <ChoiceOption>[];
    for (var n = 1; numbered.containsKey(n); n++) {
      final o = numbered[n]!;
      options.add(ChoiceOption(key: o.key, label: o.label, isSelected: o.sel));
    }
    if (options.length >= 2) {
      var q = numbered[1]!.at - 1;
      while (q >= 0 && (recent[q].trim().isEmpty || _numbered.hasMatch(recent[q]))) {
        q--;
      }
      final question = q >= 0 ? recent[q].trim() : '';
      return ChoicePrompt(question: question, options: options);
    }
  }

  // 1b) Opções inline numa linha: "1. Azul 2. Verde 3. Vermelho"
  for (var k = recent.length - 1; k >= 0 && k >= recent.length - 4; k--) {
    final inline = _inlineNumbered.allMatches(recent[k]).toList();
    if (inline.length >= 2) {
      var q = k - 1;
      while (q >= 0 && recent[q].trim().isEmpty) {
        q--;
      }
      return ChoicePrompt(
        question: q >= 0 ? recent[q].trim() : '',
        options: [
          for (final m in inline)
            ChoiceOption(key: m.group(1)!, label: m.group(2)!.trim()),
        ],
      );
    }
  }

  // 2) Sim/não: a última linha pergunta "(y/n)"
  for (var k = recent.length - 1; k >= 0 && k >= recent.length - 3; k--) {
    if (_yesNo.hasMatch(recent[k])) {
      return ChoicePrompt(
        question: recent[k].trim(),
        options: const [
          ChoiceOption(key: 'y', label: 'Sim'),
          ChoiceOption(key: 'n', label: 'Não'),
        ],
      );
    }
  }
  return null;
}

/// Atalhos `/` conhecidos de cada agente. Vazio para shell.
const Map<String, List<String>> _slashByAgent = {
  'claude_code': [
    '/help', '/clear', '/compact', '/config', '/cost', '/doctor', '/init', '/memory',
    '/model', '/permissions', '/review', '/status', '/agents', '/mcp',
  ],
  'codex': [
    '/model', '/approvals', '/status', '/new', '/init', '/compact', '/review', '/diff',
    '/mention', '/feedback', '/help', '/quit',
  ],
  'antigravity_cli': ['/help', '/clear', '/model', '/status'],
  'open_code': ['/help', '/clear', '/models', '/share', '/undo'],
};

/// Sugestões de `/comando` para o texto digitado (começando por `/`).
List<String> slashSuggestions(String? agentType, String input) {
  if (!input.startsWith('/')) return const [];
  final all = _slashByAgent[agentType] ?? const <String>[];
  final q = input.toLowerCase();
  return [for (final c in all) if (c.startsWith(q)) c];
}

/// Teclas para escolher [option] num menu: navega com as setas a partir da opção
/// marcada (ou a primeira) e confirma com Enter. Opções y/n são respondidas com a letra.
String choiceKeySequence(ChoicePrompt prompt, ChoiceOption option) {
  if (option.key == 'y' || option.key == 'n') return '${option.key}\r';
  final current = prompt.options.indexWhere((o) => o.isSelected);
  final from = current < 0 ? 0 : current;
  final to = prompt.options.indexOf(option);
  final delta = to - from;
  final arrow = delta > 0 ? '\x1b[B' : '\x1b[A';
  final keys = StringBuffer();
  for (var i = 0; i < delta.abs(); i++) {
    keys.write(arrow);
  }
  keys.write('\r');
  return keys.toString();
}
