import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/canvas/connection_kind.dart';
import 'package:maestri_wire_client/models/canvas_node.dart';
import 'package:maestri_wire_client/ui/canvas/cable_painter.dart';

Map<String, dynamic> _frame(double x, double y, [double w = 200, double h = 120]) =>
    {'x': x, 'y': y, 'width': w, 'height': h};

void main() {
  group('CanvasSnapshot', () {
    test('lê cada kind de nó, inclusive desconhecido', () {
      final snap = CanvasSnapshot.fromJson({
        'nodes': [
          {'id': 'a', 'kind': 'text', 'frame': _frame(0, 0), 'title': 'T', 'text': {'text': 'oi', 'fontSize': 18}},
          {'id': 'b', 'kind': 'file', 'frame': _frame(0, 0), 'title': 'F', 'file': {'displayName': 'x.png', 'isImage': true}},
          {'id': 'c', 'kind': 'link', 'frame': _frame(0, 0), 'title': 'L', 'link': {'url': 'https://e.x'}},
          {'id': 'd', 'kind': 'connector', 'frame': _frame(0, 0), 'title': 'C', 'connector': {'remoteTerminalId': 'r'}},
          {'id': 'e', 'kind': 'fileTree', 'frame': _frame(0, 0), 'title': 'Arvore'},
          {'id': 'f', 'kind': 'noteStack', 'frame': _frame(0, 0), 'title': 'Fich', 'noteStack': {'tabs': []}},
          {'id': 'g', 'kind': 'portal', 'frame': _frame(0, 0), 'title': 'P', 'portal': {'portalId': 'p'}},
          {'id': 'h', 'kind': 'hologram', 'frame': _frame(0, 0), 'title': 'Novo', 'isNodeLocked': true, 'groupId': 'G1', 'zIndex': 3},
        ],
      });
      expect(snap.nodes.map((n) => n.type).toList(), [
        NodeType.text,
        NodeType.file,
        NodeType.link,
        NodeType.connector,
        NodeType.fileTree,
        NodeType.noteStack,
        NodeType.portal,
        NodeType.unknown,
      ]);
      final unknown = snap.nodes.last;
      expect(unknown.kind, 'hologram');
      expect(unknown.isLocked, isTrue);
      expect(unknown.groupId, 'G1');
      expect(unknown.zIndex, 3);
      expect(snap.nodes.first.payload['fontSize'], 18);
      expect(snap.nodes.first.isConnectable, isFalse);
      expect(snap.nodes[3].isConnectable, isTrue);
    });

    test('lê cordas por kind, grupos, desenhos e abraçadeiras', () {
      final snap = CanvasSnapshot.fromJson({
        'zoom': 1.5,
        'nodes': [],
        'connections': [
          {'id': 'c1', 'fromNodeId': 'a', 'toNodeId': 'b', 'kind': 'crossFloor', 'isActive': true,
            'points': [{'x': 1, 'y': 2}, {'x': 3, 'y': 4}]},
          {'id': 'c2', 'fromNodeId': 'a', 'toNodeId': 'b', 'kind': 'alienKind'},
          {'id': '', 'fromNodeId': 'a', 'toNodeId': 'b', 'kind': 'terminal'},
        ],
        'groups': [{'id': 'G1', 'name': 'Time', 'colorHex': '#FF0000'}],
        'drawings': [
          {'id': 'd1', 'tool': 'rectangle', 'origin': [10, 20], 'size': [100, 50], 'originalSize': [50, 25],
            'color': '#00FF00', 'points': [[0, 0], [50, 25]]},
        ],
        'cableTies': [
          {'id': 't1', 'position': {'x': 5, 'y': 6}, 'memberConnectionIds': ['c1']},
          {'id': 't2', 'position': {'x': 5, 'y': 6}, 'memberConnectionIds': []},
        ],
      });
      expect(snap.zoom, 1.5);
      expect(snap.connections.map((c) => c.kind).toList(),
          [ConnectionKind.crossFloor, ConnectionKind.desconhecido]);
      expect(snap.connections.first.isActive, isTrue);
      expect(snap.groups.single.name, 'Time');
      expect(parseHexColor(snap.groups.single.colorHex), const Color(0xFFFF0000));
      expect(snap.drawings.single.canvasPoints.last, const Offset(110, 70));
      expect(snap.ties.map((t) => t.id).toList(), ['t1']);
    });

    test('entradas malformadas não derrubam o parse', () {
      final snap = CanvasSnapshot.fromJson({
        'nodes': ['lixo', {'id': 'ok', 'kind': 'text', 'frame': _frame(0, 0)}],
        'connections': 'nada',
        'drawings': null,
      });
      expect(snap.nodes.map((n) => n.id).toList(), ['ok']);
      expect(snap.connections, isEmpty);
      expect(snap.drawings, isEmpty);
    });
  });

  group('cabos', () {
    CanvasNode node(String id, double x, double y) => CanvasNode(
          id: id,
          type: NodeType.note,
          title: id,
          position: Offset(x, y),
          size: const Size(200, 100),
        );

    test('cableStyleFor distingue crossFloor e crossWorkspace como tracejados', () {
      expect(cableStyleFor(ConnectionKind.crossFloor).dashed, isTrue);
      expect(cableStyleFor(ConnectionKind.crossWorkspace).dashed, isTrue);
      expect(cableStyleFor(ConnectionKind.terminal).dashed, isFalse);
      expect(cableStyleFor(ConnectionKind.desconhecido).dashed, isFalse);
    });

    test('hitTestCable acha o cabo perto do meio e ignora o resto', () {
      final a = node('a', 0, 0);
      final b = node('b', 600, 0);
      final nodes = {'a': a, 'b': b};
      final cable = CanvasSnapshot.fromJson({
        'connections': [
          {'id': 'c', 'fromNodeId': 'a', 'toNodeId': 'b', 'kind': 'note'},
        ],
      }).connections.single;
      final path = cablePath(cable, nodes);
      expect(path, isNotNull);
      final mid = path!.computeMetrics().first.getTangentForOffset(
            path.computeMetrics().first.length / 2,
          )!.position;
      expect(hitTestCable(mid, [cable], nodes)?.id, 'c');
      expect(hitTestCable(const Offset(300, 900), [cable], nodes), isNull);
    });

    test('modo circuit ignora os pontos do host e desenha das pontas', () {
      final a = node('a', 0, 0);
      final b = node('b', 600, 0);
      final cable = CanvasSnapshot.fromJson({
        'connections': [
          {'id': 'c', 'fromNodeId': 'a', 'toNodeId': 'b', 'kind': 'terminal',
            'points': [{'x': 9999, 'y': 9999}, {'x': 9998, 'y': 9999}]},
        ],
      }).connections.single;
      final nodes = {'a': a, 'b': b};
      final fromPoints = cablePath(cable, nodes)!.getBounds();
      final fromEnds = cablePath(cable, nodes, fromEndpoints: true)!.getBounds();
      expect(fromPoints.right, greaterThan(9000));
      expect(fromEnds.right, lessThan(700));
    });

    test('cabo com ponta fora do andar não tem caminho', () {
      final cable = CanvasSnapshot.fromJson({
        'connections': [
          {'id': 'c', 'fromNodeId': 'a', 'toNodeId': 'fora', 'kind': 'crossFloor'},
        ],
      }).connections.single;
      expect(cablePath(cable, {'a': node('a', 0, 0)}), isNull);
    });
  });
}
