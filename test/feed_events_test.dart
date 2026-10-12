import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/network/feed_events.dart';

const _epochA = '6f1c2b9e-0d3a-4c1e-9b7a-2e5f8a1d4c10';
const _epochB = 'a9d4e7f2-5b3c-4e8a-8f1d-7c2b6e9a0f33';
const _floor = '0b7e5c3a-9f2d-4a6b-8c1e-3d5f7a9b1c2e';

String _mutation({
  required int sequence,
  String epoch = _epochA,
  String? mutationId,
  String kindJson = '{"kind":"nodeRemoved","nodeId":"n-1"}',
}) {
  final id = mutationId == null ? '' : '"mutationId":"$mutationId",';
  return '{"type":"mutation","mutation":{$id"sequence":$sequence,'
      '"epoch":"$epoch","floorId":"$_floor",'
      '"actor":{"deviceId":"dev-1","deviceName":"iPhone da Ana","role":"owner"},'
      '"kind":$kindJson}}';
}

MutationEvent _event({required int sequence, String epoch = _epochA}) {
  final msg = parseFeedMessage(_mutation(sequence: sequence, epoch: epoch));
  return (msg as FeedMutationMessage).mutation;
}

void main() {
  group('parseFeedMessage', () {
    test('feed com snapshot cru', () {
      final msg = parseFeedMessage(
        '{"type":"feed","snapshot":{"workspaceId":"ws-1","nodes":[]}}',
      );
      expect(msg, isA<FeedSnapshotMessage>());
      final snap = (msg as FeedSnapshotMessage).snapshot;
      expect(snap['workspaceId'], 'ws-1');
      expect(snap['nodes'], isEmpty);
    });

    test('pong', () {
      expect(parseFeedMessage('{"type":"pong"}'), isA<FeedPongMessage>());
    });

    test('type desconhecido vira FeedUnknownMessage', () {
      final msg = parseFeedMessage('{"type":"algoNovo","x":1}');
      expect(msg, isA<FeedUnknownMessage>());
      expect((msg as FeedUnknownMessage).type, 'algoNovo');
      expect(msg.raw['x'], 1);
    });

    test('JSON inválido, sem type ou não-objeto retornam null', () {
      expect(parseFeedMessage('não é json'), isNull);
      expect(parseFeedMessage('{"foo":1}'), isNull);
      expect(parseFeedMessage('[1,2]'), isNull);
      expect(parseFeedMessage('{"type":"feed"}'), isNull);
    });

    test('mutation sem sequence ou epoch retorna null', () {
      expect(
        parseFeedMessage('{"type":"mutation","mutation":{"epoch":"$_epochA",'
            '"kind":{"kind":"nodeRemoved","nodeId":"n"}}}'),
        isNull,
      );
      expect(
        parseFeedMessage('{"type":"mutation","mutation":{"sequence":3,'
            '"kind":{"kind":"nodeRemoved","nodeId":"n"}}}'),
        isNull,
      );
    });

    test('mutation completa com actor, floorId e mutationId', () {
      final msg = parseFeedMessage(_mutation(
        sequence: 41,
        mutationId: 'req-7',
        kindJson: '{"kind":"nodeMoved","nodeId":"n-1",'
            '"frame":{"x":100,"y":200,"width":260,"height":200}}',
      ));
      final e = (msg as FeedMutationMessage).mutation;
      expect(e.sequence, 41);
      expect(e.epoch, _epochA);
      expect(e.mutationId, 'req-7');
      expect(e.floorId, _floor);
      expect(e.actor!.deviceId, 'dev-1');
      expect(e.actor!.deviceName, 'iPhone da Ana');
      expect(e.actor!.role, 'owner');
      final kind = e.kind as NodeMovedKind;
      expect(kind.nodeId, 'n-1');
      expect(kind.frame.x, 100);
      expect(kind.frame.width, 260);
    });

    test('mutation sem opcionais (mutationId, floorId, actor)', () {
      final msg = parseFeedMessage('{"type":"mutation","mutation":'
          '{"sequence":1,"epoch":"$_epochA",'
          '"kind":{"kind":"drawingRemoved","drawingId":"d-9"}}}');
      final e = (msg as FeedMutationMessage).mutation;
      expect(e.mutationId, isNull);
      expect(e.floorId, isNull);
      expect(e.actor, isNull);
      expect((e.kind as DrawingRemovedKind).drawingId, 'd-9');
    });

    test('os 12 tipos de kind do contrato são parseados', () {
      final cases = <String, String>{
        '{"kind":"nodeMoved","nodeId":"n","frame":{"x":0,"y":0,"width":1,"height":1}}':
            'nodeMoved',
        '{"kind":"nodeRenamed","nodeIds":["a","b"],"name":"Deploy"}':
            'nodeRenamed',
        '{"kind":"nodeCreated","nodeId":"n","nodeKind":"note"}': 'nodeCreated',
        '{"kind":"nodeRemoved","nodeId":"n"}': 'nodeRemoved',
        '{"kind":"nodeLockChanged","nodeId":"n","isLocked":true}':
            'nodeLockChanged',
        '{"kind":"noteColorChanged","nodeId":"n","color":"yellow"}':
            'noteColorChanged',
        '{"kind":"connectionAdded","fromNodeId":"a","toNodeId":"b"}':
            'connectionAdded',
        '{"kind":"connectionRemoved","fromNodeId":"a","toNodeId":"b"}':
            'connectionRemoved',
        '{"kind":"noteStackRailChanged","stackNodeId":"s","memberNodeIds":["a"],"frontNoteId":"a"}':
            'noteStackRailChanged',
        '{"kind":"drawingAdded","drawingId":"d"}': 'drawingAdded',
        '{"kind":"drawingRemoved","drawingId":"d"}': 'drawingRemoved',
        '{"kind":"drawingMoved","drawingId":"d","origin":[120,340]}':
            'drawingMoved',
      };
      for (final entry in cases.entries) {
        final msg = parseFeedMessage(
          _mutation(sequence: 1, kindJson: entry.key),
        ) as FeedMutationMessage;
        expect(msg.mutation.kind, isNot(isA<UnknownMutationKind>()),
            reason: entry.value);
        expect(msg.mutation.kind.kind, entry.value);
      }
    });

    test('nodeRenamed, noteColorChanged e drawingMoved mantêm campos', () {
      final renamed = (parseFeedMessage(_mutation(
        sequence: 2,
        kindJson: '{"kind":"nodeRenamed","nodeIds":["a","b"],"name":"Deploy"}',
      )) as FeedMutationMessage).mutation.kind as NodeRenamedKind;
      expect(renamed.nodeIds, ['a', 'b']);
      expect(renamed.name, 'Deploy');

      final color = (parseFeedMessage(_mutation(
        sequence: 3,
        kindJson: '{"kind":"noteColorChanged","nodeId":"n","color":"custom",'
            '"customColor":"#FF8800"}',
      )) as FeedMutationMessage).mutation.kind as NoteColorChangedKind;
      expect(color.customColor, '#FF8800');

      final moved = (parseFeedMessage(_mutation(
        sequence: 4,
        kindJson: '{"kind":"drawingMoved","drawingId":"d","origin":{"x":5,"y":6}}',
      )) as FeedMutationMessage).mutation.kind as DrawingMovedKind;
      expect(moved.origin.x, 5);
      expect(moved.origin.y, 6);
    });

    test('kind desconhecido é preservado, não descartado', () {
      final msg = parseFeedMessage(_mutation(
        sequence: 9,
        kindJson: '{"kind":"futurePowerUp","nodeId":"n","extra":{"a":1}}',
      )) as FeedMutationMessage;
      expect(msg.mutation.sequence, 9);
      final kind = msg.mutation.kind as UnknownMutationKind;
      expect(kind.kind, 'futurePowerUp');
      expect(kind.raw['nodeId'], 'n');
      expect((kind.raw['extra'] as Map)['a'], 1);
    });

    test('kind conhecido com campo faltando também vira desconhecido', () {
      final msg = parseFeedMessage(_mutation(
        sequence: 10,
        kindJson: '{"kind":"nodeMoved","nodeId":"n"}',
      )) as FeedMutationMessage;
      expect(msg.mutation.kind, isA<UnknownMutationKind>());
      expect(msg.mutation.kind.kind, 'nodeMoved');
    });

    test('exemplo literal do contrato, em JSON cru', () {
      final raw = jsonEncode({
        'type': 'mutation',
        'mutation': {
          'mutationId': 'abc-123',
          'sequence': 1042,
          'epoch': _epochA,
          'floorId': _floor,
          'actor': {'deviceId': 'd', 'deviceName': 'Mac'},
          'kind': {'kind': 'connectionAdded', 'fromNodeId': 'a', 'toNodeId': 'b'},
        },
      });
      final msg = parseFeedMessage(raw) as FeedMutationMessage;
      expect(msg.mutation.actor!.role, isNull);
      expect(msg.mutation.kind, isA<ConnectionAddedKind>());
    });
  });

  group('MutationTracker', () {
    test('sequência normal é aplicada', () {
      final t = MutationTracker();
      expect(t.accept(_event(sequence: 1)), MutationDecision.apply);
      expect(t.accept(_event(sequence: 2)), MutationDecision.apply);
      expect(t.accept(_event(sequence: 3)), MutationDecision.apply);
      expect(t.lastSequence, 3);
      expect(t.epoch, _epochA);
    });

    test('duplicado (mesmo epoch e sequence) é ignorado', () {
      final t = MutationTracker();
      t.accept(_event(sequence: 1));
      t.accept(_event(sequence: 2));
      expect(t.accept(_event(sequence: 2)), MutationDecision.duplicate);
      expect(t.accept(_event(sequence: 1)), MutationDecision.duplicate);
      expect(t.lastSequence, 2);
      expect(t.accept(_event(sequence: 3)), MutationDecision.apply);
    });

    test('mesmo mutationId com sequence nova não é tratado como duplicado', () {
      final t = MutationTracker();
      final first = (parseFeedMessage(_mutation(sequence: 1, mutationId: 'x'))
          as FeedMutationMessage).mutation;
      final second = (parseFeedMessage(_mutation(sequence: 2, mutationId: 'x'))
          as FeedMutationMessage).mutation;
      expect(t.accept(first), MutationDecision.apply);
      expect(t.accept(second), MutationDecision.apply);
    });

    test('lacuna de sequence exige ressincronizar', () {
      final t = MutationTracker();
      t.accept(_event(sequence: 5));
      t.accept(_event(sequence: 6));
      expect(t.accept(_event(sequence: 9)), MutationDecision.resync);
      // Depois da ressincronização, a nova sequência continua a partir de 9.
      expect(t.accept(_event(sequence: 10)), MutationDecision.apply);
    });

    test('epoch novo exige ressincronizar e reinicia a sequência', () {
      final t = MutationTracker();
      t.accept(_event(sequence: 1));
      t.accept(_event(sequence: 2));
      expect(
        t.accept(_event(sequence: 1, epoch: _epochB)),
        MutationDecision.resync,
      );
      expect(t.epoch, _epochB);
      expect(t.lastSequence, 1);
      expect(t.accept(_event(sequence: 2, epoch: _epochB)), MutationDecision.apply);
      // Um evento do epoch antigo, mesmo com sequence válida, não é aplicado.
      expect(
        t.accept(_event(sequence: 3, epoch: _epochA)),
        MutationDecision.resync,
      );
    });

    test('primeiro evento estabelece a baseline; reset a limpa', () {
      final t = MutationTracker();
      expect(t.accept(_event(sequence: 70)), MutationDecision.apply);
      t.reset();
      expect(t.epoch, isNull);
      expect(t.lastSequence, isNull);
      expect(t.accept(_event(sequence: 1, epoch: _epochB)), MutationDecision.apply);
    });
  });

  group('builders cliente -> servidor', () {
    test('presence com nodeId', () {
      expect(
        jsonDecode(presenceNodeMessage('node-42')),
        {'type': 'presence', 'nodeId': 'node-42'},
      );
    });

    test('presence com point', () {
      expect(
        jsonDecode(presencePointMessage(120, 340.5)),
        {
          'type': 'presence',
          'point': {'x': 120, 'y': 340.5},
        },
      );
      expect(() => presencePointMessage(double.nan, 0), throwsArgumentError);
    });

    test('presence vazio (sair de um nó)', () {
      expect(jsonDecode(presenceClearMessage()), {'type': 'presence'});
    });

    test('ping', () {
      expect(jsonDecode(pingMessage()), {'type': 'ping'});
    });

    test('camera com pan e zoom dentro dos limites', () {
      expect(
        jsonDecode(cameraMessage(dx: 12, dy: -4, zoom: 1.02)),
        {
          'type': 'camera',
          'pan': {'dx': 12, 'dy': -4},
          'zoom': 1.02,
        },
      );
    });

    test('camera limita pan a ±4000 e zoom a 0.25..4', () {
      final big = jsonDecode(cameraMessage(dx: 9000, dy: -9000, zoom: 10))
          as Map<String, dynamic>;
      expect(big['pan'], {'dx': 4000, 'dy': -4000});
      expect(big['zoom'], 4);

      final small = jsonDecode(cameraMessage(zoom: 0.01)) as Map<String, dynamic>;
      expect(small['zoom'], 0.25);
    });

    test('camera omite pan zero e zoom ausente; não-finitos viram nada', () {
      expect(jsonDecode(cameraMessage()), {'type': 'camera'});
      expect(
        jsonDecode(cameraMessage(dx: double.nan, dy: 3, zoom: double.infinity)),
        {
          'type': 'camera',
          'pan': {'dx': 0, 'dy': 3},
        },
      );
    });
  });
}
