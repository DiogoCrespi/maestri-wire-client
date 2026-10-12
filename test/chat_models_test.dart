import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/chat_attachment.dart';
import 'package:maestri_wire_client/models/chat_mention.dart';
import 'package:maestri_wire_client/models/chat_thread.dart';
import 'package:maestri_wire_client/models/terminal_chat.dart';

void main() {
  test('snapshot lê threads, canClear e showsShellWindow do host', () {
    final snap = ChatSnapshot.fromJson({
      'terminalId': 't',
      'conversationId': 'c',
      'enabled': true,
      'status': 'idle',
      'entries': <dynamic>[],
      'canClear': false,
      'showsShellWindow': false,
      'hasOlderOnRecord': true,
      'threads': {
        'activeSlot': 2,
        'canSelect': true,
        'items': [
          {'id': 0, 'color': 'blue', 'hasMessages': true},
          {'id': 1, 'color': 'purple', 'hasMessages': false},
          {'id': 2, 'color': 'pink', 'hasMessages': true},
        ],
      },
    });

    expect(snap.enabled, isTrue);
    expect(snap.canClear, isFalse);
    expect(snap.showsShellWindow, isFalse);
    expect(snap.hasOlderOnRecord, isTrue);
    expect(snap.threads, isNotNull);
    expect(snap.threads!.activeSlot, 2);
    expect(snap.threads!.canSelect, isTrue);
    expect(snap.threads!.items.map((i) => i.color), ['blue', 'purple', 'pink']);
    expect(snap.threads!.items[1].hasMessages, isFalse);
  });

  test('host antigo sem threads nem showsShellWindow: sem controles de thread e janela aberta', () {
    final snap = ChatSnapshot.fromJson({
      'terminalId': 't',
      'conversationId': 'c',
      'enabled': false,
      'status': 'notRunning',
      'entries': <dynamic>[],
    });
    expect(snap.threads, isNull);
    expect(snap.showsShellWindow, isTrue);
    expect(snap.canClear, isTrue);
  });

  test('entrada do usuário guarda os anexos dos segmentos, na ordem', () {
    final entry = ChatEntry.fromJson({
      'id': 'e1',
      'role': 'user',
      'kind': 'message',
      'ts': '2026-10-11T10:00:00Z',
      'text': 'olha isso',
      'segments': [
        {'text': 'olha isso'},
        {
          'attachment': {
            'id': '6F1C1D2E-0000-4000-8000-000000000001',
            'isImage': true,
            'filename': 'foto.png',
            'contentType': 'public.png',
          }
        },
      ],
    });

    expect(entry.isUser, isTrue);
    expect(entry.attachments, hasLength(1));
    expect(entry.attachments.first.filename, 'foto.png');
    expect(entry.attachments.first.isImage, isTrue);
  });

  test('tipo de entrada desconhecido vira other', () {
    expect(ChatEntryKind.parse('novidade'), ChatEntryKind.other);
    expect(ChatEntryKind.parse('final'), ChatEntryKind.finalAnswer);
  });

  test('anexo preparado lê id, nome, tipo e validade', () {
    final att = ChatAttachment.fromJson({
      'attachmentId': 'a-1',
      'fileName': 'nota.pdf',
      'mimeType': 'application/pdf',
      'expiresAt': '2026-10-11T10:15:00Z',
    });
    expect(att.attachmentId, 'a-1');
    expect(att.isImage, isFalse);
    expect(att.expiresAt, DateTime.parse('2026-10-11T10:15:00Z'));
  });

  test('segmentos do prompt serializam como {text} e {attachmentId}', () {
    final segments = <PromptSegment>[
      const TextSegment('oi'),
      const AttachmentSegment('a-1'),
    ];
    final body = jsonDecode(jsonEncode({
      'segments': [for (final s in segments) s.toJson()],
    })) as Map<String, dynamic>;
    expect(body['segments'], [
      {'text': 'oi'},
      {'attachmentId': 'a-1'},
    ]);
  });

  test('menção insere @tokenName quando existe, senão @name', () {
    final agent = ChatMention.fromJson({
      'kind': 'agent',
      'id': 'x',
      'name': 'Codex #2',
      'tokenName': 'codex2',
      'floorName': 'Térreo',
    });
    final note = ChatMention.fromJson({'kind': 'note', 'id': 'y', 'name': 'Plano'});
    expect(agent.insertText, '@codex2');
    expect(note.insertText, '@Plano');
  });

  test('lista de menções ignora itens malformados e ações desconhecidas são mantidas', () {
    final list = ChatMention.listFromJson({
      'mentions': [
        {'kind': 'createNote', 'id': 'a', 'name': 'New Note'},
        'lixo',
        {'kind': 'futuro', 'id': 'b', 'name': 'Algo'},
      ],
    });
    expect(list.map((m) => m.kind), ['createNote', 'futuro']);
    expect(ChatMention.listFromJson({}), isEmpty);
  });

  test('listagem de arquivos lê entradas, pastas e truncamento', () {
    final listing = ChatFileListing.fromJson({
      'query': 'rel',
      'root': '/home/x',
      'entries': [
        {'relativePath': 'docs', 'name': 'docs', 'isDirectory': true},
        {'relativePath': 'docs/relatorio.md', 'name': 'relatorio.md', 'isDirectory': false},
      ],
      'isTruncated': true,
    });
    expect(listing.query, 'rel');
    expect(listing.isTruncated, isTrue);
    expect(listing.entries.first.isDirectory, isTrue);
    expect(listing.entries.last.relativePath, 'docs/relatorio.md');
  });

  test('threads: canSelect falso e slots fora de ordem preservam a ordem do host', () {
    final threads = ChatThreads.fromJson({
      'activeSlot': 0,
      'canSelect': false,
      'items': [
        for (var i = 0; i < 7; i++) {'id': i, 'color': 'blue', 'hasMessages': false},
      ],
    });
    expect(threads.canSelect, isFalse);
    expect(threads.items.map((t) => t.id), [0, 1, 2, 3, 4, 5, 6]);
  });
}
