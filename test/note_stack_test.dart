import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/note_stack.dart';

Map<String, dynamic> stackNode() => {
      'id': '5b0c1f7e-0000-4000-8000-000000000001',
      'kind': 'noteStack',
      'title': 'Ideias',
      'frame': {'x': 0, 'y': 0, 'width': 260, 'height': 200},
      'noteStack': {
        'name': 'Ideias',
        'hasCustomName': true,
        'tabs': [
          {'nodeId': 'n1', 'title': 'Primeira', 'color': 'yellow'},
          {'nodeId': 'n2', 'title': 'Segunda', 'color': 'blue'},
          {'nodeId': 'n3', 'title': 'Terceira'},
        ],
        'frontNoteId': 'n2',
        'front': {
          'nodeId': 'n2',
          'fileName': 'segunda.md',
          'displayName': 'Segunda',
          'color': 'blue',
          'preview': ['texto'],
          'isExternal': false,
        },
        'uniformColor': false,
      },
    };

void main() {
  test('lê o nó noteStack do canvas com abas e frente', () {
    final stack = NoteStack.fromCanvasNode(stackNode())!;
    expect(stack.nodeId, '5b0c1f7e-0000-4000-8000-000000000001');
    expect(stack.name, 'Ideias');
    expect(stack.hasCustomName, isTrue);
    expect(stack.tabs.map((t) => t.nodeId), ['n1', 'n2', 'n3']);
    expect(stack.tabs[2].color, isNull);
    expect(stack.frontNoteId, 'n2');
    expect(stack.frontTitle, 'Segunda');
    expect(stack.frontColor, 'blue');
  });

  test('um nó que não é fichário retorna null', () {
    expect(NoteStack.fromCanvasNode({'id': 'x', 'kind': 'note', 'note': {}}), isNull);
  });

  test('withRail reordena abas, troca a frente e remove páginas arquivadas', () {
    final stack = NoteStack.fromCanvasNode(stackNode())!;
    final next = stack.withRail(const NoteStackRail(
      memberNodeIds: ['n3', 'n1'],
      frontNoteId: 'n1',
    ));
    expect(next.tabs.map((t) => t.nodeId), ['n3', 'n1']);
    expect(next.frontNoteId, 'n1');
    // a original continua imutável
    expect(stack.tabs.length, 3);
  });

  test('withTabColor troca só a cor da aba indicada', () {
    final stack = NoteStack.fromCanvasNode(stackNode())!;
    final next = stack.withTabColor('n3', 'green');
    expect(next.tabs[2].color, 'green');
    expect(next.tabs[0].color, 'yellow');
    expect(next.tabs[1].color, 'blue');
  });

  test('displayTitle usa a página da frente quando o fichário não tem nome próprio', () {
    final stack = NoteStack.fromCanvasNode(stackNode())!;
    expect(stack.displayTitle, 'Ideias');
    final unnamed = NoteStack.fromCanvasNode({
      ...stackNode(),
      'noteStack': {
        ...(stackNode()['noteStack'] as Map<String, dynamic>),
        'name': 'Térreo',
        'hasCustomName': false,
      },
    })!;
    expect(unnamed.displayTitle, 'Segunda');
  });

  test('a paleta de cores tem as chaves do host', () {
    expect(kNoteColorKeys, containsAll(['yellow', 'blue', 'green', 'graphite']));
  });
}
