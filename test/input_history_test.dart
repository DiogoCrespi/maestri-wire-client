import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/terminal/input_history.dart';

void main() {
  test('↑ recupera a última mensagem enviada', () {
    final h = InputHistory()..add('primeira')..add('segunda');
    expect(h.previous(''), 'segunda');
    expect(h.previous(''), 'primeira');
    expect(h.previous(''), 'primeira'); // para na mais antiga
  });

  test('↓ avança e volta ao rascunho digitado', () {
    final h = InputHistory()..add('um')..add('dois');
    expect(h.previous('rascunho em curso'), 'dois');
    expect(h.next(), 'rascunho em curso');
  });

  test('sem histórico não devolve nada', () {
    final h = InputHistory();
    expect(h.previous('x'), isNull);
    expect(h.next(), isNull);
  });

  test('mensagem vazia não entra no histórico e envio zera a navegação', () {
    final h = InputHistory()..add('   ')..add('ok');
    expect(h.previous(''), 'ok');
    h.add('novo');
    expect(h.isBrowsing, isFalse);
    expect(h.previous(''), 'novo');
  });
}
