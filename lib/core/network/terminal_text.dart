import 'dart:convert';

/// Decodificador UTF-8 incremental. Guarda apenas os bytes finais de um caractere
/// incompleto e devolve, a cada chamada, o texto já completo.
class Utf8StreamDecoder {
  final List<int> _pending = [];

  String add(List<int> bytes) {
    _pending.addAll(bytes);
    final cut = _completeLength(_pending);
    if (cut == 0) return '';
    final text = utf8.decode(_pending.sublist(0, cut), allowMalformed: true);
    _pending.removeRange(0, cut);
    return text;
  }

  /// Tamanho do prefixo que termina em um caractere completo.
  static int _completeLength(List<int> bytes) {
    final len = bytes.length;
    // Um caractere UTF-8 tem no máximo 4 bytes: só o final pode estar incompleto
    for (var i = len - 1; i >= 0 && i >= len - 4; i--) {
      final b = bytes[i];
      if (b & 0xC0 == 0x80) continue; // continuação
      final expected = b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : b >= 0xC0 ? 2 : 1;
      return i + expected > len ? i : len;
    }
    return len;
  }
}

/// Emulador de tela suficiente para TUIs como o Codex e o Claude Code:
/// grade de linhas x colunas com cursor, posicionamento absoluto e relativo
/// (CUP, CUU, CUD, CUF, CUB, CHA, VPA), apagamento (ED, EL) e quebra de linha.
/// Cores e atributos são ignorados. Linhas que saem pelo topo vão para [scrollback].
class TerminalScreen {
  static const int _maxScrollback = 5000;

  int rows;
  int cols;
  late List<List<int>> _grid;
  int _row = 0;
  int _col = 0;
  bool _autowrap = true;
  bool _alternate = false;

  /// Verdadeiro dentro da tela alternativa (ESC[?1049h), usada por TUIs como Codex.
  /// Fora dela a saída é de shell e vira conversa crua.
  bool get alternate => _alternate;

  /// Linha onde o cursor está (a que ainda está sendo escrita).
  int get cursorRow => _row;

  final List<String> scrollback = [];

  _Esc _state = _Esc.normal;
  final StringBuffer _params = StringBuffer();

  TerminalScreen({this.rows = 30, this.cols = 100}) {
    _grid = _blankGrid();
  }

  /// Redimensiona mantendo o conteúdo que cabe.
  void resize({required int rows, required int cols}) {
    if (rows == this.rows && cols == this.cols) return;
    final old = _grid;
    this.rows = rows;
    this.cols = cols;
    _grid = _blankGrid();
    for (var r = 0; r < rows && r < old.length; r++) {
      for (var c = 0; c < cols && c < old[r].length; c++) {
        _grid[r][c] = old[r][c];
      }
    }
    _row = _row.clamp(0, rows - 1);
    _col = _col.clamp(0, cols - 1);
  }

  /// Conteúdo atual da tela, uma string por linha, sem espaços à direita.
  List<String> get screenLines => [
        for (final line in _grid) String.fromCharCodes(line).trimRight(),
      ];

  void write(String text) {
    for (final rune in text.runes) {
      _feed(rune);
    }
  }

  List<List<int>> _blankGrid() =>
      List.generate(rows, (_) => List.filled(cols, 0x20));

  void _feed(int rune) {
    switch (_state) {
      case _Esc.normal:
        _normal(rune);
      case _Esc.escape:
        if (rune == 0x5B) {
          // '[' -> CSI
          _params.clear();
          _state = _Esc.csi;
        } else if (rune == 0x5D) {
          // ']' -> OSC, termina em BEL ou ESC \
          _state = _Esc.osc;
        } else {
          // Escape de dois caracteres (ex.: ESC 7, ESC =): ignorado
          _state = _Esc.normal;
        }
      case _Esc.csi:
        if (rune >= 0x40 && rune <= 0x7E) {
          _csi(String.fromCharCode(rune));
          _state = _Esc.normal;
        } else if (rune == 0x1B) {
          _state = _Esc.escape;
        } else if (rune >= 0x20 && rune <= 0x3F) {
          _params.writeCharCode(rune);
        }
      case _Esc.osc:
        if (rune == 0x07) {
          _state = _Esc.normal;
        } else if (rune == 0x1B) {
          _state = _Esc.escape;
        }
    }
  }

  void _normal(int rune) {
    switch (rune) {
      case 0x1B:
        _state = _Esc.escape;
      case 0x0D: // \r
        _col = 0;
      case 0x0A: // \n
        _lineFeed();
      case 0x08: // backspace
        if (_col > 0) _col--;
      case 0x09: // tab
        _col = ((_col ~/ 8) + 1) * 8;
        if (_col >= cols) _col = cols - 1;
      default:
        if (rune < 0x20 || rune == 0x7F) return; // outros controles
        _put(rune);
    }
  }

  void _put(int rune) {
    if (_col >= cols) {
      if (_autowrap) {
        _col = 0;
        _lineFeed();
      } else {
        _col = cols - 1;
      }
    }
    _grid[_row][_col] = rune;
    _col++;
  }

  void _lineFeed() {
    if (_row < rows - 1) {
      _row++;
      return;
    }
    // Rola a tela: a linha de cima vai para o histórico
    scrollback.add(String.fromCharCodes(_grid.first).trimRight());
    if (scrollback.length > _maxScrollback) {
      scrollback.removeRange(0, scrollback.length - _maxScrollback);
    }
    _grid
      ..removeAt(0)
      ..add(List.filled(cols, 0x20));
  }

  void _csi(String finalByte) {
    final raw = _params.toString();
    final private = raw.startsWith('?');
    final nums = raw
        .replaceAll('?', '')
        .split(';')
        .map((p) => int.tryParse(p))
        .toList();
    int arg(int i, int fallback) {
      if (i >= nums.length) return fallback;
      final v = nums[i];
      return v == null || v == 0 ? fallback : v;
    }

    switch (finalByte) {
      case 'H':
      case 'f':
        _row = (arg(0, 1) - 1).clamp(0, rows - 1);
        _col = (arg(1, 1) - 1).clamp(0, cols - 1);
      case 'A':
        _row = (_row - arg(0, 1)).clamp(0, rows - 1);
      case 'B':
        _row = (_row + arg(0, 1)).clamp(0, rows - 1);
      case 'C':
        _col = (_col + arg(0, 1)).clamp(0, cols - 1);
      case 'D':
        _col = (_col - arg(0, 1)).clamp(0, cols - 1);
      case 'G':
        _col = (arg(0, 1) - 1).clamp(0, cols - 1);
      case 'd':
        _row = (arg(0, 1) - 1).clamp(0, rows - 1);
      case 'J':
        _eraseDisplay(nums.isEmpty ? 0 : (nums.first ?? 0));
      case 'K':
        _eraseLine(nums.isEmpty ? 0 : (nums.first ?? 0));
      case 'h':
      case 'l':
        // Modo privado 7 = quebra automática de linha
        if (private && nums.contains(7)) _autowrap = finalByte == 'h';
        if (private && (nums.contains(1049) || nums.contains(47))) {
          _alternate = finalByte == 'h';
        }
      default:
        // Cores (m), margens e demais sequências não mudam o texto
        break;
    }
  }

  void _eraseDisplay(int mode) {
    switch (mode) {
      case 0:
        _eraseLine(0);
        for (var r = _row + 1; r < rows; r++) {
          _grid[r].fillRange(0, cols, 0x20);
        }
      case 1:
        _eraseLine(1);
        for (var r = 0; r < _row; r++) {
          _grid[r].fillRange(0, cols, 0x20);
        }
      default:
        for (final line in _grid) {
          line.fillRange(0, cols, 0x20);
        }
    }
  }

  void _eraseLine(int mode) {
    final line = _grid[_row];
    switch (mode) {
      case 0:
        line.fillRange(_col, cols, 0x20);
      case 1:
        line.fillRange(0, _col + 1 > cols ? cols : _col + 1, 0x20);
      default:
        line.fillRange(0, cols, 0x20);
    }
  }
}

enum _Esc { normal, escape, csi, osc }

/// Tipo de bloco exibido na conversa, classificado pelo prefixo que a TUI usa.
enum TerminalBlockKind { user, agent, status, raw }

class TerminalBlock {
  final TerminalBlockKind kind;
  final List<String> lines;

  const TerminalBlock(this.kind, this.lines);

  String get text => lines.join('\n').trim();
}

/// Conversa montada a partir da saída do terminal.
///
/// A tela (TUI) é emulada em [TerminalScreen]. A cada atualização:
/// - linhas que rolaram para o histórico de um shell viram blocos permanentes;
/// - a tela da TUI é classificada em blocos. Mensagens do usuário, respostas do
///   agente e "Worked for …" entram no histórico sem duplicar; o status
///   "Working (…)" é transitório e fica só enquanto o agente trabalha;
/// - texto de chrome da TUI (rodapé, placeholder, atalhos) é descartado.
class TerminalConversation {
  final TerminalScreen screen;
  final List<TerminalBlock> _history = [];
  final Utf8StreamDecoder _utf8 = Utf8StreamDecoder();
  TerminalBlock? _working;
  int _scrollbackSeen = 0;

  TerminalConversation({int rows = 30, int cols = 100})
      : screen = TerminalScreen(rows: rows, cols: cols);

  /// Blocks da conversa, em ordem, com o status de trabalho no fim (se houver).
  List<TerminalBlock> get blocks =>
      [..._history, if (_working != null) _working!];

  /// Texto completo para copiar.
  String get plainText => blocks.map((b) => b.lines.join('\n')).join('\n');

  bool get isEmpty => blocks.isEmpty;

  void addBytes(List<int> bytes) => _apply(_utf8.add(bytes));

  void addText(String text) => _apply(text);

  /// Mensagem enviada por este app: entra no histórico sem passar pela tela da TUI.
  void addUserMessage(String text) =>
      _merge(TerminalBlock(TerminalBlockKind.user, [text]), fromScrollback: false);

  void resize({required int rows, required int cols}) =>
      screen.resize(rows: rows, cols: cols);

  void clear() {
    _history.clear();
    _working = null;
    _scrollbackSeen = 0;
    screen.scrollback.clear();
  }

  void _apply(String text) {
    if (text.isEmpty) return;
    screen.write(text);

    // Histórico de shell: linhas que rolaram para fora da tela
    final fresh = screen.scrollback.sublist(_scrollbackSeen);
    _scrollbackSeen = screen.scrollback.length;
    for (final block in groupTerminalBlocks(
      fresh.where((l) => !_isChrome(l)).toList(),
    )) {
      _merge(block, fromScrollback: true);
    }

    // Tela atual. Em TUI (tela alternativa) a saída crua é descartada, e a conversa
    // vem das mensagens classificadas. Fora dela é shell: a saída crua vai para a conversa.
    _working = null;
    final rawAllowed = !screen.alternate;
    final lines = screen.screenLines;
    if (rawAllowed) {
      // Linha em edição ainda é parcial (ex.: só o primeiro byte de um caractere):
      // não promove para a conversa até ela ser concluída.
      lines[screen.cursorRow] = '';
    }
    final visible = groupTerminalBlocks(
      lines.where((l) => !_isChrome(l)).toList(),
    );
    for (final block in visible) {
      _merge(block, fromScrollback: rawAllowed);
    }
  }

  void _merge(TerminalBlock block, {required bool fromScrollback}) {
    if (block.text.isEmpty) return;

    if (block.kind == TerminalBlockKind.status && _isWorking(block.text)) {
      _working = block;
      return;
    }
    // Linhas cruas da tela podem ser recortes da TUI (topo da viewport): só o
    // histórico de shell guarda saída crua.
    if (block.kind == TerminalBlockKind.raw && !fromScrollback) return;

    // Já está no histórico?
    final start = _history.length > 300 ? _history.length - 300 : 0;
    for (var i = start; i < _history.length; i++) {
      final existing = _history[i];
      if (existing.kind == block.kind && existing.text == block.text) return;
    }

    // Resposta que cresce (streaming): substitui a versão anterior
    if (_history.isNotEmpty) {
      final last = _history.last;
      if (last.kind == block.kind &&
          (block.kind == TerminalBlockKind.agent ||
              block.kind == TerminalBlockKind.user) &&
          block.text.startsWith(last.text)) {
        _history[_history.length - 1] = block;
        return;
      }
    }

    _history.add(block);
    if (_history.length > 2000) {
      _history.removeRange(0, _history.length - 2000);
    }
  }
}

/// Placeholder do campo de entrada do Codex: aparece com `› ` mas não foi enviado pelo usuário.
bool _isComposerPlaceholder(String text) =>
    text.trim() == 'Ask Codex to do anything';

/// Chrome da TUI: rodapé, atalhos e placeholder. Não faz parte da conversa.
bool _isChrome(String line) {
  final t = line.trim();
  if (t.isEmpty) return false;
  if (t.contains('for shortcuts') || t.contains('f2 to view')) return true;
  if (_isComposerPlaceholder(t.startsWith('› ') ? t.substring(2) : t)) {
    return true;
  }
  if (RegExp(r'^(GPT|Claude|Opus|Sonnet|Haiku)\S* .*·').hasMatch(t)) return true;
  if (t.startsWith('─') || t.startsWith('━')) return true;
  // Claude Code: spinner com contagem de tokens, dicas e barra de modo
  if (RegExp(r'tokens\)\s*$').hasMatch(t)) return true;
  if (RegExp(r'^[⎿↳└]?\s*Tip:').hasMatch(t)) return true;
  if (t.contains('shift+tab to cycle') || t.startsWith('auto mode on')) return true;
  // Linha do composer vazio (prompt sem texto)
  if (t == '❯' || t == '>') return true;
  return false;
}

/// Agrupa linhas em blocos de conversa:
/// `› ` / `❯ ` inicia mensagem do usuário, `• ` / `● ` inicia resposta do agente,
/// "Working (…)" / "Worked for …" / "Brewed for …" é status.
/// Linhas seguintes sem prefixo continuam o bloco anterior.
List<TerminalBlock> groupTerminalBlocks(List<String> lines) {
  final blocks = <TerminalBlock>[];
  TerminalBlockKind? openKind;
  List<String>? openLines;

  void close() {
    final kind = openKind;
    final ls = openLines;
    if (kind != null && ls != null) {
      blocks.add(TerminalBlock(kind, ls));
    }
    openKind = null;
    openLines = null;
  }

  void open(TerminalBlockKind kind, String firstLine) {
    close();
    openKind = kind;
    openLines = [firstLine];
  }

  for (final line in lines) {
    final trimmed = line.trimLeft();
    // Status vem antes de tudo: "• Working (…)" é status, não resposta
    final body = trimmed.startsWith('• ') || trimmed.startsWith('✻ ')
        ? trimmed.substring(2)
        : trimmed;
    if (_isStatusText(body)) {
      open(TerminalBlockKind.status, body.trim());
    } else if (trimmed.startsWith('› ') || trimmed.startsWith('❯ ')) {
      final text = trimmed.substring(2);
      if (_isComposerPlaceholder(text)) {
        open(TerminalBlockKind.raw, text);
      } else {
        open(TerminalBlockKind.user, text);
      }
    } else if (trimmed.startsWith('• ') || trimmed.startsWith('● ')) {
      open(TerminalBlockKind.agent, trimmed.substring(2));
    } else if (openKind == TerminalBlockKind.agent) {
      // Resposta do agente continua sem prefixo (quebra de linha da TUI)
      openLines!.add(line);
    } else if (openKind == TerminalBlockKind.user && line.startsWith('  ')) {
      openLines!.add(line);
    } else if (openKind == TerminalBlockKind.raw) {
      openLines!.add(line);
    } else {
      open(TerminalBlockKind.raw, line);
    }
  }
  close();

  return blocks.where((b) => b.text.isNotEmpty).toList();
}

/// Blocos de conversa de um preview de terminal (texto do feed), sem o ruído do TUI.
/// Usado pelos cards do canvas.
List<TerminalBlock> terminalPreviewBlocks(List<String> lines) {
  return groupTerminalBlocks(lines.where((l) => !_isChrome(l)).toList());
}

bool _isStatusText(String text) {
  return text.startsWith('Working (') ||
      text.startsWith('Worked for ') ||
      text.startsWith('Brewed for ') ||
      text.contains('esc to interrupt');
}

bool _isWorking(String text) =>
    text.startsWith('Working (') || text.contains('esc to interrupt');
