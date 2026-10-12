import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/terminal_chat.dart';

void main() {
  test('lê um snapshot real do host (chat desligado, sem entradas)', () {
    final snap = ChatSnapshot.fromJson({
      'terminalId': '9c0cee2a-eb36-4912-b43e-8abef059f791',
      'conversationId': '9C0CEE2A-EB36-4912-B43E-8ABEF059F791',
      'enabled': false,
      'entries': <dynamic>[],
      'hasOlderOnRecord': false,
      'status': 'idle',
      'turnInterrupted': false,
      'unreadCount': 0,
      'canClear': true,
      'showsShellWindow': true,
    });

    expect(snap.enabled, isFalse);
    expect(snap.entries, isEmpty);
    expect(snap.isWorking, isFalse);
  });

  test('classifica mensagem do usuário, progresso e resposta final', () {
    final snap = ChatSnapshot.fromJson({
      'terminalId': 't',
      'conversationId': 'c',
      'enabled': true,
      'status': 'working',
      'hasOlderOnRecord': true,
      'entries': [
        {
          'id': 'e1',
          'role': 'user',
          'ts': '2026-10-11T19:31:00Z',
          'kind': 'message',
          'text': 'opa tá chegando?',
          'segments': [
            {'text': 'opa tá chegando?'}
          ],
        },
        {
          'id': 'e2',
          'role': 'agent',
          'ts': '2026-10-11T19:31:02Z',
          'kind': 'progress',
          'text': 'Lendo o cadastro…',
          'authorName': 'Codex',
          'agentType': 'codex',
          'segments': <dynamic>[],
        },
        {
          'id': 'e3',
          'role': 'agent',
          'ts': '2026-10-11T19:31:05Z',
          'kind': 'final',
          'text': 'Sim, chegou.',
          'segments': <dynamic>[],
        },
        {
          'id': 'e4',
          'role': 'agent',
          'kind': 'algum-tipo-novo',
          'text': 'futuro',
        },
      ],
    });

    expect(snap.isWorking, isTrue);
    expect(snap.hasOlderOnRecord, isTrue);
    expect(snap.entries.map((e) => e.kind).toList(), [
      ChatEntryKind.message,
      ChatEntryKind.progress,
      ChatEntryKind.finalAnswer,
      ChatEntryKind.other,
    ]);
    expect(snap.entries[0].isUser, isTrue);
    expect(snap.entries[1].isUser, isFalse);
    expect(snap.entries[1].authorName, 'Codex');
    expect(snap.entries[2].text, 'Sim, chegou.');
    expect(snap.entries[0].timestamp, DateTime.utc(2026, 10, 11, 19, 31));
  });

  test('entradas malformadas são ignoradas sem derrubar o snapshot', () {
    final snap = ChatSnapshot.fromJson({
      'terminalId': 't',
      'conversationId': 'c',
      'enabled': true,
      'entries': [
        'lixo',
        {'id': 'ok', 'role': 'agent', 'kind': 'final', 'text': 'fim'},
      ],
    });
    expect(snap.entries.length, 1);
    expect(snap.entries.single.text, 'fim');
  });
}
