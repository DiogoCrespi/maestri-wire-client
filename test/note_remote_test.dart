import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/note_content.dart';
import 'package:maestri_wire_client/models/note_stack.dart';
import 'package:maestri_wire_client/ui/widgets/stack_picker.dart';

void main() {
  group('mutações ao vivo', () {
    final stack = {'a'};

    test('rail do fichário vale pelo stackNodeId ou por página que entra/sai', () {
      expect(
        isNoteRemoteChange({'kind': 'noteStackRailChanged', 'stackNodeId': 'a', 'memberNodeIds': []}, stack),
        isTrue,
      );
      expect(
        isNoteRemoteChange(
          {'kind': 'noteStackRailChanged', 'stackNodeId': 'z', 'memberNodeIds': ['x', 'a']},
          stack,
        ),
        isTrue,
      );
      expect(
        isNoteRemoteChange(
          {'kind': 'noteStackRailChanged', 'stackNodeId': 'z', 'memberNodeIds': ['x']},
          stack,
        ),
        isFalse,
      );
    });

    test('cor, remoção e trava valem pelo nodeId', () {
      for (final k in ['noteColorChanged', 'nodeRemoved', 'nodeLockChanged']) {
        expect(isNoteRemoteChange({'kind': k, 'nodeId': 'a'}, stack), isTrue, reason: k);
        expect(isNoteRemoteChange({'kind': k, 'nodeId': 'q'}, stack), isFalse, reason: k);
      }
    });

    test('rename vale se algum dos nodeIds é observado', () {
      expect(isNoteRemoteChange({'kind': 'nodeRenamed', 'nodeIds': ['q', 'a']}, stack), isTrue);
      expect(isNoteRemoteChange({'kind': 'nodeRenamed', 'nodeIds': ['q']}, stack), isFalse);
    });

    test('snapshot do feed sempre manda reler; tipos desconhecidos e moves não', () {
      expect(isNoteRemoteChange({'kind': kNoteFeedSnapshotKind}, stack), isTrue);
      expect(isNoteRemoteChange({'kind': 'drawingAdded', 'drawingId': 'a'}, stack), isFalse);
      expect(isNoteRemoteChange({'kind': 'nodeMoved', 'nodeId': 'a'}, stack), isFalse);
    });
  });

  group('NoteCandidate', () {
    test('lê note do FeedItem com nome próprio ou primeira linha', () {
      final custom = NoteCandidate.fromFeedItem({
        'kind': 'note',
        'note': {
          'nodeId': 'n1',
          'fileName': 'a.md',
          'displayName': 'Ideias',
          'color': 'blue',
          'floorName': 'Térreo',
          'preview': ['linha'],
          'isExternal': false,
          'hasCustomName': true,
        },
      })!;
      expect(custom.nodeId, 'n1');
      expect(custom.title, 'Ideias');
      expect(custom.color, 'blue');
      expect(custom.floorName, 'Térreo');

      final unnamed = NoteCandidate.fromFeedItem({
        'kind': 'note',
        'note': {'nodeId': 'n2', 'fileName': 'x.md', 'displayName': 'x', 'preview': ['Primeira linha']},
      })!;
      expect(unnamed.title, 'Primeira linha');
    });

    test('ignora itens que não são nota', () {
      expect(NoteCandidate.fromFeedItem({'kind': 'terminal', 'terminal': {}}), isNull);
    });
  });

  group('seleção do fichário', () {
    const notes = [
      NoteCandidate(nodeId: 'a', title: 'A'),
      NoteCandidate(nodeId: 'b', title: 'B'),
      NoteCandidate(nodeId: 'c', title: 'C'),
    ];

    test('desmarcar tira da lista e preserva a ordem', () {
      expect(stackPickerSelection(notes, {'b'}), ['a', 'c']);
      expect(stackPickerSelection(notes, {}), ['a', 'b', 'c']);
    });

    test('ids repetidos não entram duas vezes', () {
      const dup = [NoteCandidate(nodeId: 'a', title: 'A'), NoteCandidate(nodeId: 'a', title: 'A')];
      expect(stackPickerSelection(dup, {}), ['a']);
    });
  });

  test('withLocked muda só a trava', () {
    const note = NoteContent(
      nodeId: 'n',
      displayName: 'n',
      text: 't',
      revision: 'r',
      isLocked: false,
    );
    final locked = note.withLocked(true);
    expect(locked.isLocked, isTrue);
    expect(locked.text, 't');
    expect(locked.revision, 'r');
  });
}
