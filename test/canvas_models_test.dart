import 'dart:convert';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/canvas/cable_tie_group.dart';
import 'package:maestri_wire_client/models/canvas/canvas_group.dart';
import 'package:maestri_wire_client/models/canvas/connection.dart';
import 'package:maestri_wire_client/models/canvas/connection_kind.dart';
import 'package:maestri_wire_client/models/canvas/connector_node.dart';
import 'package:maestri_wire_client/models/canvas/drawing.dart';
import 'package:maestri_wire_client/models/canvas/file_node.dart';
import 'package:maestri_wire_client/models/canvas/link_node.dart';
import 'package:maestri_wire_client/models/canvas/route.dart';
import 'package:maestri_wire_client/models/canvas/text_block.dart';

Object? j(String s) => jsonDecode(s);

void main() {
  group('TextBlock (payload text)', () {
    test('exemplo do contrato', () {
      final t = TextBlock.fromJson(
        j('{"text":"Olá","fontSize":18,"isMonospaced":true,"color":"#FF0000",'
                '"fontFamily":"serif","fontWeight":"bold","fontName":"Georgia"}')
            as Map<String, dynamic>,
      );
      expect(t.text, 'Olá');
      expect(t.fontSize, 18);
      expect(t.isMonospaced, isTrue);
      expect(t.color, '#FF0000');
      expect(t.fontFamily, 'serif');
      expect(t.fontWeight, 'bold');
      expect(t.fontName, 'Georgia');
    });

    test('malformado usa defaults', () {
      final t = TextBlock.fromJson({'text': 42, 'fontSize': 'grande', 'isMonospaced': 'sim'});
      expect(t.text, '');
      expect(t.fontSize, 14);
      expect(t.isMonospaced, isFalse);
      expect(t.color, isNull);
    });

    test('listFromJson ignora entradas inválidas', () {
      final list = TextBlock.listFromJson(j('[{"text":"a"}, 7, null, "x", {"text":"b"}]'));
      expect(list.map((t) => t.text), ['a', 'b']);
      expect(TextBlock.listFromJson(null), isEmpty);
      expect(TextBlock.listFromJson('nope'), isEmpty);
    });
  });

  group('FileNode (payload file)', () {
    test('exemplo do contrato', () {
      final f = FileNode.fromJson(
        j('{"displayName":"foto.png","caption":"capa","isImage":true,"isVideo":false}')
            as Map<String, dynamic>,
      );
      expect(f.displayName, 'foto.png');
      expect(f.caption, 'capa');
      expect(f.isImage, isTrue);
      expect(f.isVideo, isFalse);
    });

    test('malformado e lista', () {
      final f = FileNode.fromJson({'displayName': null, 'isVideo': 1});
      expect(f.displayName, '');
      expect(f.isVideo, isFalse);
      final list = FileNode.listFromJson(j('[{"displayName":"a.mp4","isVideo":true}, 3]'));
      expect(list, hasLength(1));
      expect(list.single.isVideo, isTrue);
    });
  });

  group('LinkNode (payload link)', () {
    test('exemplo e malformados', () {
      final l = LinkNode.fromJson(
        j('{"url":"https://example.com","title":"Exemplo"}') as Map<String, dynamic>,
      );
      expect(l.url, 'https://example.com');
      expect(l.title, 'Exemplo');

      final list = LinkNode.listFromJson(j('[{"title":"sem url"}, {"url":""}, {"url":"https://a.b"}, "lixo"]'));
      expect(list.map((x) => x.url), ['https://a.b']);
    });
  });

  group('ConnectorNode (payload connector)', () {
    test('cross-floor e cross-workspace', () {
      final f = ConnectorNode.fromJson(
        j('{"remoteTerminalId":"t-1","remoteFloorId":"f-2"}') as Map<String, dynamic>,
      );
      expect(f.remoteFloorId, 'f-2');
      expect(f.remoteWorkspaceId, isNull);
      expect(f.isCrossWorkspace, isFalse);

      final w = ConnectorNode.fromJson(
        j('{"remoteTerminalId":"t-9","remoteFloorId":"f-1","remoteWorkspaceId":"ws-7"}')
            as Map<String, dynamic>,
      );
      expect(w.remoteWorkspaceId, 'ws-7');
      expect(w.isCrossWorkspace, isTrue);
    });

    test('lista descarta sem remoteTerminalId', () {
      final list = ConnectorNode.listFromJson(j('[{"remoteFloorId":"f"}, {"remoteTerminalId":"t"}]'));
      expect(list.map((c) => c.remoteTerminalId), ['t']);
    });
  });

  group('CableTieGroup', () {
    test('exemplo do contrato', () {
      final t = CableTieGroup.fromJson(
        j('{"id":"tie-1","position":{"x":120,"y":80.5},'
                '"memberConnectionIds":["11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222"]}')
            as Map<String, dynamic>,
      );
      expect(t.id, 'tie-1');
      expect(t.position, const Offset(120, 80.5));
      expect(t.memberConnectionIds, hasLength(2));
      expect(t.memberConnectionIds.first, '11111111-1111-1111-1111-111111111111');
    });

    test('listFromJson descarta sem id, sem position, sem cordas ou tipo errado', () {
      final list = CableTieGroup.listFromJson(j('''[
        {"id":"ok","position":[10,20],"memberConnectionIds":["c1",3,"c2"]},
        {"id":"sem-pos","memberConnectionIds":["c1"]},
        {"id":"vazia","position":{"x":0,"y":0},"memberConnectionIds":[]},
        {"position":{"x":0,"y":0},"memberConnectionIds":["c1"]},
        {"id":"pos-ruim","position":"aqui","memberConnectionIds":["c1"]},
        "lixo"
      ]'''));
      expect(list.map((t) => t.id), ['ok']);
      expect(list.single.memberConnectionIds, ['c1', 'c2']);
    });
  });

  group('CanvasGroup', () {
    test('exemplo e malformados', () {
      final g = CanvasGroup.fromJson(
        j('{"id":"g1","name":"Backend","colorHex":"#3366FF"}') as Map<String, dynamic>,
      );
      expect(g.name, 'Backend');
      expect(g.colorHex, '#3366FF');

      final list = CanvasGroup.listFromJson(j('[{"name":"sem id"}, {"id":"g2"}, 1]'));
      expect(list.map((x) => x.id), ['g2']);
      expect(list.single.name, '');
    });
  });

  group('ConnectionKind', () {
    test('todos os valores do contrato e fallback', () {
      expect(ConnectionKind.parse('terminal'), ConnectionKind.terminal);
      expect(ConnectionKind.parse('note'), ConnectionKind.note);
      expect(ConnectionKind.parse('noteToNote'), ConnectionKind.noteToNote);
      expect(ConnectionKind.parse('portal'), ConnectionKind.portal);
      expect(ConnectionKind.parse('portalToPortal'), ConnectionKind.portalToPortal);
      expect(ConnectionKind.parse('crossFloor'), ConnectionKind.crossFloor);
      expect(ConnectionKind.parse('crossWorkspace'), ConnectionKind.crossWorkspace);
      expect(ConnectionKind.parse('algumaCoisaNova'), ConnectionKind.desconhecido);
      expect(ConnectionKind.parse(null), ConnectionKind.desconhecido);
      expect(ConnectionKind.parse(5), ConnectionKind.desconhecido);
      expect(ConnectionKind.crossFloor.wire, 'crossFloor');
    });
  });

  group('Connection', () {
    test('exemplo do contrato', () {
      final c = Connection.fromJson(
        j('{"id":"c-1","fromNodeId":"n-1","toNodeId":"n-2","kind":"noteToNote","isActive":true,'
                '"points":[{"x":0,"y":0},{"x":10,"y":5}],"fromNoteNodeId":"p-1","toNoteNodeId":"p-2"}')
            as Map<String, dynamic>,
      );
      expect(c.id, 'c-1');
      expect(c.kind, ConnectionKind.noteToNote);
      expect(c.isActive, isTrue);
      expect(c.points, [const Offset(0, 0), const Offset(10, 5)]);
      expect(c.fromNoteNodeId, 'p-1');
      expect(c.toNoteNodeId, 'p-2');
    });

    test('kind desconhecido não derruba e listFromJson descarta sem ids', () {
      final list = Connection.listFromJson(j('''[
        {"id":"a","fromNodeId":"x","toNodeId":"y","kind":"futuro","points":"nada"},
        {"id":"b","fromNodeId":"x"},
        {"fromNodeId":"x","toNodeId":"y"},
        42
      ]'''));
      expect(list, hasLength(1));
      expect(list.single.kind, ConnectionKind.desconhecido);
      expect(list.single.points, isEmpty);
      expect(list.single.isActive, isFalse);
    });
  });

  group('Drawing', () {
    test('exemplo do contrato com escala e conexões', () {
      final d = Drawing.fromJson(
        j('{"id":"d-1","tool":"arrow","points":[[0,0],[50,100]],"origin":[200,300],'
                '"originalSize":[100,100],"size":[200,400],"color":"#112233","lineWidth":3,'
                '"opacity":0.8,"zIndex":4,"isLocked":false,"rotation":90,'
                '"textContent":"oi","textFontSize":12,'
                '"sourceConnection":{"drawingId":"d-0","edge":"right"},'
                '"targetConnection":{"drawingId":"d-2","edge":"left"},'
                '"strokePattern":"dashed","fillStyle":"tint","cornerRadius":6,'
                '"controlPointOffset":[5,-5],"groupId":"g1"}')
            as Map<String, dynamic>,
      );
      expect(d.tool, 'arrow');
      expect(d.points, [const Offset(0, 0), const Offset(50, 100)]);
      expect(d.origin, const Offset(200, 300));
      expect(d.originalSize, const Size(100, 100));
      expect(d.size, const Size(200, 400));
      expect(d.color, '#112233');
      expect(d.lineWidth, 3);
      expect(d.opacity, 0.8);
      expect(d.zIndex, 4);
      expect(d.rotation, 90);
      expect(d.textContent, 'oi');
      expect(d.sourceConnection!.drawingId, 'd-0');
      expect(d.sourceConnection!.edge, 'right');
      expect(d.targetConnection!.edge, 'left');
      expect(d.strokePattern, 'dashed');
      expect(d.fillStyle, 'tint');
      expect(d.cornerRadius, 6);
      expect(d.controlPointOffset, const Offset(5, -5));
      expect(d.groupId, 'g1');
      // escala: size / originalSize = (2, 4)
      expect(d.scale, const Size(2, 4));
      expect(d.canvasPoints, [const Offset(200, 300), const Offset(300, 700)]);
    });

    test('malformado usa defaults e não quebra', () {
      final d = Drawing.fromJson({
        'id': 'd-x',
        'tool': 7,
        'points': [
          [1, 2],
          ['a', 'b'],
          {'x': 3, 'y': 4},
          [5],
        ],
        'origin': 'lá',
        'size': [10, 10],
        'zIndex': '3',
        'sourceConnection': {'edge': 'top'},
        'targetConnection': 'nope',
      });
      expect(d.tool, 'pen');
      expect(d.points, [const Offset(1, 2), const Offset(3, 4)]);
      expect(d.origin, Offset.zero);
      expect(d.originalSize, const Size(10, 10));
      expect(d.zIndex, 0);
      expect(d.sourceConnection, isNull);
      expect(d.targetConnection, isNull);
      // sem originalSize válido, a escala é 1
      expect(d.scale, const Size(1, 1));
    });

    test('listFromJson descarta sem id', () {
      final list = Drawing.listFromJson(j('[{"tool":"rectangle"}, {"id":"ok","tool":"ellipse"}, null]'));
      expect(list.map((d) => d.id), ['ok']);
      expect(list.single.tool, 'ellipse');
    });
  });

  group('routeEndpoints', () {
    test('ponta na borda, na direção do outro retângulo', () {
      const a = Rect.fromLTWH(0, 0, 100, 50); // centro (50, 25)
      const b = Rect.fromLTWH(300, 25, 100, 50); // centro (350, 50)
      final p = routeEndpoints(a, b);
      // direção (300, 25): cruza a borda direita (x=100) em t=50/300
      expect(p.dx, closeTo(100, 1e-9));
      expect(p.dy, closeTo(25 + 25 * (50 / 300), 1e-9));
      // o ponto de b olhando para a fica na borda esquerda de b
      final q = routeEndpoints(b, a);
      expect(q.dx, closeTo(300, 1e-9));
    });

    test('alinhado vertical e centros coincidentes', () {
      const a = Rect.fromLTWH(0, 0, 100, 100);
      const b = Rect.fromLTWH(0, 300, 100, 100);
      expect(routeEndpoints(a, b), const Offset(50, 100));
      expect(routeEndpoints(a, a), a.center);
    });
  });

  group('listas nulas (groups/cableTies ausentes)', () {
    test('cableTies e groups opcionais', () {
      expect(CableTieGroup.listFromJson(null), isEmpty);
      expect(CanvasGroup.listFromJson(null), isEmpty);
      expect(Drawing.listFromJson(null), isEmpty);
      expect(Connection.listFromJson(null), isEmpty);
    });
  });
}
