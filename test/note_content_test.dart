import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/note_content.dart';

void main() {
  test('lê o NoteContent devolvido pelo host (formato real)', () {
    final note = NoteContent.fromJson({
      'nodeId': '07e39e07-eacb-4d3c-a51e-45dd02bcfeef',
      'fileName': 'teste.md',
      'displayName': 'teste-do-app',
      'text': '# Teste do app\nnota de validacao',
      'color': 'yellow',
      'revision': '91c7481e90592b31',
      'lastModifiedAt': '2026-10-11T19:50:00Z',
      'isExternal': false,
      'isContentLocked': true,
    });
    expect(note.displayName, 'teste-do-app');
    expect(note.revision, '91c7481e90592b31');
    expect(note.isLocked, isTrue);
    expect(note.text.split('\n').first, '# Teste do app');
  });
}
