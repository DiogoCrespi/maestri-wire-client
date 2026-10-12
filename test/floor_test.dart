import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/network/api_floors.dart';
import 'package:maestri_wire_client/models/floor.dart';
import 'package:maestri_wire_client/ui/widgets/floor_selector.dart';

void main() {
  group('FloorMeta', () {
    test('térreo não tem id e usa ground como queryValue', () {
      final f = FloorMeta.fromJson({'name': 'Térreo', 'isActive': true});
      expect(f.isGround, isTrue);
      expect(f.id, isNull);
      expect(f.queryValue, 'ground');
      expect(f.isActive, isTrue);
    });

    test('andar real usa o UUID como queryValue e lê atenção e status', () {
      final f = FloorMeta.fromJson({
        'id': '6f1c2a3e-0000-4000-8000-000000000001',
        'name': 'feat-x',
        'isGitIsolated': true,
        'branch': 'feat/x',
        'attentionCount': 2,
        'hasActivity': true,
        'isDormant': false,
        'status': {
          'state': 'working',
          'text': '  Migrando o feed  ',
          'progress': 0.4,
          'author': 'Claude',
        },
      });
      expect(f.isGround, isFalse);
      expect(f.queryValue, '6f1c2a3e-0000-4000-8000-000000000001');
      expect(f.attentionCount, 2);
      expect(f.isGitIsolated, isTrue);
      expect(f.branch, 'feat/x');
      expect(f.status!.state, 'working');
      expect(f.status!.text, 'Migrando o feed');
      expect(f.status!.progress, 0.4);
      expect(f.status!.author, 'Claude');
      expect(f.status!.isKnownState, isTrue);
    });

    test('campos ausentes ou de tipo errado usam padrões seguros', () {
      final f = FloorMeta.fromJson({'id': '', 'attentionCount': 'x'});
      expect(f.isGround, isTrue);
      expect(f.attentionCount, 0);
      expect(f.isActive, isFalse);
      expect(f.status, isNull);
      expect(f.pullRequest, isNull);
    });

    test('listFromJson é tolerante a ausência e entradas inválidas', () {
      expect(FloorMeta.listFromJson(null), isEmpty);
      expect(FloorMeta.listFromJson('nope'), isEmpty);
      final list = FloorMeta.listFromJson([
        {'name': 'Térreo'},
        42,
        {'id': 'u1', 'name': 'a'},
      ]);
      expect(list.map((f) => f.name), ['Térreo', 'a']);
    });

    test('displayOrder põe andares do mais novo ao mais antigo e o térreo por último', () {
      final floors = [
        const FloorMeta(name: 'Térreo'),
        const FloorMeta(id: 'a', name: 'antigo'),
        const FloorMeta(id: 'b', name: 'novo'),
      ];
      expect(FloorMeta.displayOrder(floors).map((f) => f.name),
          ['novo', 'antigo', 'Térreo']);
    });
  });

  group('FloorStatus', () {
    test('estado desconhecido é preservado e não quebra o parse', () {
      final s = FloorStatus.tryFromJson({'state': 'paused', 'text': 'espera'});
      expect(s, isNotNull);
      expect(s!.state, 'paused');
      expect(s.isKnownState, isFalse);
    });

    test('sem texto não há status', () {
      expect(FloorStatus.tryFromJson({'state': 'done', 'text': '   '}), isNull);
      expect(FloorStatus.tryFromJson(null), isNull);
    });

    test('progresso fora de 0…1 ou não finito é descartado', () {
      expect(FloorStatus.tryFromJson({'state': 'working', 'text': 't', 'progress': 40})!.progress, isNull);
      expect(FloorStatus.tryFromJson({'state': 'working', 'text': 't', 'progress': -0.1})!.progress, isNull);
      expect(FloorStatus.tryFromJson({'state': 'working', 'text': 't', 'progress': 1})!.progress, 1);
    });
  });

  group('FloorPullRequest', () {
    test('lê número, atenção e flags', () {
      final pr = FloorPullRequest.tryFromJson({
        'state': 'open',
        'isDraft': true,
        'number': 42,
        'attention': 'checksFailing',
        'title': 'Andares',
        'isReadOnly': true,
      })!;
      expect(pr.number, 42);
      expect(pr.isDraft, isTrue);
      expect(pr.attention, 'checksFailing');
      expect(pr.isReadOnly, isTrue);
      expect(pr.isReview, isFalse);
    });
  });

  group('FloorApiException', () {
    test('lê code e message do formato de erro do host', () {
      final e = FloorApiException.fromResponse(
        404,
        '{"error":{"code":"notFound","message":"Not found"}}',
      );
      expect(e.statusCode, 404);
      expect(e.code, 'notFound');
      expect(e.message, 'Not found');
    });

    test('corpo que não é JSON vira a mensagem crua', () {
      final e = FloorApiException.fromResponse(503, 'indisponível');
      expect(e.code, 'http503');
      expect(e.message, 'indisponível');
    });
  });

  group('FloorSelector', () {
    final floors = [
      const FloorMeta(name: 'Térreo', isActive: true, attentionCount: 2),
      const FloorMeta(
        id: 'u1',
        name: 'feat-x',
        status: FloorStatus(state: 'blocked', text: 'esperando revisão'),
        pullRequest: FloorPullRequest(number: 7, attention: 'conflicts', title: 'PR'),
      ),
    ];

    Future<void> pumpSelector(
      WidgetTester tester, {
      required ValueChanged<FloorMeta> onView,
      Future<void> Function(FloorMeta)? onActivate,
      String? viewingFloor,
    }) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FloorSelector(
            floors: floors,
            onView: onView,
            onActivate: onActivate,
            viewingFloor: viewingFloor,
          ),
        ),
      ));
    }

    testWidgets('mostra andares na ordem de exibição, atenção e status', (tester) async {
      await pumpSelector(tester, onView: (_) {});
      // novo primeiro (feat-x) e térreo por último
      final feat = tester.getTopLeft(find.text('feat-x')).dy;
      final ground = tester.getTopLeft(find.text('Térreo')).dy;
      expect(feat, lessThan(ground));
      expect(find.text('2'), findsOneWidget); // badge de atenção do térreo
      expect(find.text('No host agora'), findsOneWidget);
      expect(find.textContaining('Bloqueado: esperando revisão'), findsOneWidget);
      expect(find.textContaining('#7'), findsOneWidget);
      expect(find.textContaining('conflitos'), findsOneWidget);
    });

    testWidgets('tocar em um andar chama onView sem ativar', (tester) async {
      FloorMeta? viewed;
      var activated = false;
      await pumpSelector(
        tester,
        onView: (f) => viewed = f,
        onActivate: (_) async => activated = true,
      );
      await tester.tap(find.text('feat-x'));
      await tester.pump();
      expect(viewed?.id, 'u1');
      expect(activated, isFalse);
    });

    testWidgets('botão Ativar só aparece em andares não ativos e chama onActivate', (tester) async {
      FloorMeta? activated;
      await pumpSelector(
        tester,
        onView: (_) {},
        onActivate: (f) async => activated = f,
      );
      // só o feat-x não está ativo no host
      expect(find.text('Ativar'), findsOneWidget);
      await tester.tap(find.text('Ativar'));
      await tester.pumpAndSettle();
      expect(activated?.id, 'u1');
    });

    testWidgets('sem onActivate não há botão Ativar', (tester) async {
      await pumpSelector(tester, onView: (_) {});
      expect(find.text('Ativar'), findsNothing);
    });
  });
}
