import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/note_content.dart';
import 'package:maestri_wire_client/models/note_stack.dart';

// Os corpos abaixo seguem o contrato de Escritas no canvas / Notas do host.
// A chamada HTTP em si (lib/core/network/api_notes.dart) é validada no host real.
void main() {
  test('stack/front, stack/order e stack/pages respondem {ok, memberNodeIds, frontNoteId}', () {
    final rail = NoteStackRail.fromJson({
      'ok': true,
      'memberNodeIds': ['a', 'b', 'c'],
      'frontNoteId': 'b',
    });
    expect(rail.memberNodeIds, ['a', 'b', 'c']);
    expect(rail.frontNoteId, 'b');
  });

  test('stack/pages DELETE sem frente devolve frontNoteId ausente', () {
    final rail = NoteStackRail.fromJson({
      'ok': true,
      'memberNodeIds': <String>[],
    });
    expect(rail.memberNodeIds, isEmpty);
    expect(rail.frontNoteId, isNull);
  });

  test('note/color devolve NoteContent com cor', () {
    final note = NoteContent.fromJson({
      'nodeId': 'n1',
      'fileName': 'a.md',
      'displayName': 'a',
      'text': 'x',
      'color': 'green',
      'revision': '0123456789abcdef',
      'lastModifiedAt': '2026-10-11T00:00:00Z',
      'isExternal': false,
      'isContentLocked': false,
    });
    expect(note.color, 'green');
    expect(note.isLocked, isFalse);
  });
}
