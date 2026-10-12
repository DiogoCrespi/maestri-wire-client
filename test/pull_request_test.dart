import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/pull_request.dart';

void main() {
  group('PullRequestContext', () {
    test('lê o contexto e os agentes do andar', () {
      final ctx = PullRequestContext.fromJson({
        'title': 'Feat X',
        'body': 'corpo',
        'base': 'main',
        'providerName': 'GitHub',
        'account': 'acme',
        'supportsDraft': true,
        'unpushedCommits': 2,
        'agents': [
          {'id': 't1', 'name': 'Claude', 'isRunning': true},
          {'id': '', 'name': 'sem id'},
          {'id': 't2'},
        ],
      });
      expect(ctx.base, 'main');
      expect(ctx.supportsDraft, isTrue);
      expect(ctx.unpushedCommits, 2);
      expect(ctx.problem, isNull);
      expect(ctx.agents.map((a) => a.id), ['t1', 't2']);
      expect(ctx.agents.last.name, 'Agente');
    });

    test('problema do host é mostrado; provedor ausente vira null', () {
      final ctx = PullRequestContext.fromJson({
        'problem': 'Sem remote',
        'providerName': '   ',
      });
      expect(ctx.problem, 'Sem remote');
      expect(ctx.providerName, isNull);
      expect(ctx.agents, isEmpty);
    });
  });

  group('pullRequestOpenBody', () {
    test('omite draft e onWebsite quando não informados', () {
      final body = pullRequestOpenBody(base: ' main ', title: ' T ', body: 'B');
      expect(body, {'base': 'main', 'title': 'T', 'body': 'B'});
      expect(body.containsKey('draft'), isFalse);
      expect(body.containsKey('onWebsite'), isFalse);
    });

    test('inclui draft e onWebsite quando informados', () {
      final body = pullRequestOpenBody(
        base: 'main',
        title: 'T',
        body: '',
        draft: true,
        onWebsite: false,
      );
      expect(body['draft'], isTrue);
      expect(body['onWebsite'], isFalse);
    });
  });

  group('PullRequestOpened / PullRequestRemoved', () {
    test('leem url opcional e merge destino', () {
      expect(PullRequestOpened.fromJson({'openedOnWebsite': true}).url, isNull);
      expect(PullRequestOpened.fromJson({'url': 'https://x/1'}).url, 'https://x/1');
      final removed = PullRequestRemoved.fromJson({'branch': 'feat/x', 'mergedInto': 'main'});
      expect(removed.mergedInto, 'main');
    });
  });

  test('valores fixos das rotas têm rótulos', () {
    for (final m in pullRequestMergeMethods) {
      expect(pullRequestMergeLabel(m), isNot(m));
    }
    expect(pullRequestTaskLabel('assess'), 'Avaliar revisão');
    expect(pullRequestTaskLabel('outra'), 'outra');
  });
}
