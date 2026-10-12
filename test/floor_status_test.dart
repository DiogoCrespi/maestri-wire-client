import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/floor.dart';
import 'package:maestri_wire_client/ui/widgets/floor_status_editor.dart';

void main() {
  group('statusProgressFor', () {
    test('mantém o progresso enquanto o estado não muda', () {
      expect(
        statusProgressFor(initialState: 'working', newState: 'working', initialProgress: 0.4),
        0.4,
      );
    });

    test('descarta o progresso quando o estado muda', () {
      expect(
        statusProgressFor(initialState: 'working', newState: 'review', initialProgress: 0.4),
        isNull,
      );
    });

    test('sem estado inicial, não há progresso a manter', () {
      expect(
        statusProgressFor(initialState: null, newState: 'done', initialProgress: null),
        isNull,
      );
    });
  });

  group('FloorStatus', () {
    test('estado desconhecido é preservado e o progresso fora de 0..1 é descartado', () {
      final status = FloorStatus.tryFromJson({
        'state': 'paused-by-moon',
        'text': 'Esperando',
        'progress': 1.5,
      })!;
      expect(status.state, 'paused-by-moon');
      expect(status.isKnownState, isFalse);
      expect(status.progress, isNull);
    });

    test('texto vazio não vira status', () {
      expect(FloorStatus.tryFromJson({'state': 'working', 'text': '   '}), isNull);
    });
  });
}
