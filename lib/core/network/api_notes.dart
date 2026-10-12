import 'dart:convert';
import 'dart:io';

import '../../models/note_content.dart';
import '../../models/note_stack.dart';
import 'wire_client.dart';

/// Rotas de fichário (note stacks), renomear e cor de nota.
/// Todas são escritas (owner ou papel com escrita) e respondem `{ok}` ou o recurso.
extension NotesApi on WireClient {
  /// `GET /api/workspaces/{ws}/feed`: acha o nó `noteStack` pelo id no canvas.
  Future<NoteStack?> loadNoteStack({
    required String workspaceId,
    required String stackNodeId,
  }) async {
    final feed = await getJson('/api/workspaces/$workspaceId/feed');
    final canvas = feed['canvas'];
    final nodes = canvas is Map ? canvas['nodes'] : null;
    if (nodes is! List) return null;
    for (final node in nodes) {
      if (node is Map<String, dynamic> && node['id'] == stackNodeId) {
        return NoteStack.fromCanvasNode(node);
      }
    }
    return null;
  }

  /// `PUT …/nodes/{id}/stack/front`: vira o fichário para uma página.
  Future<NoteStackRail> setStackFront({
    required String workspaceId,
    required String stackNodeId,
    required String frontNoteId,
  }) async {
    final json = await _notesWrite(
      'PUT',
      '/api/workspaces/$workspaceId/nodes/$stackNodeId/stack/front',
      {'frontNoteId': frontNoteId},
      'stack/front',
    );
    return NoteStackRail.fromJson(json);
  }

  /// `PUT …/nodes/{id}/stack/order`: `memberNodeIds` deve ser uma permutação das páginas atuais.
  Future<NoteStackRail> reorderStackPages({
    required String workspaceId,
    required String stackNodeId,
    required List<String> memberNodeIds,
  }) async {
    final json = await _notesWrite(
      'PUT',
      '/api/workspaces/$workspaceId/nodes/$stackNodeId/stack/order',
      {'memberNodeIds': memberNodeIds},
      'stack/order',
    );
    return NoteStackRail.fromJson(json);
  }

  /// `POST …/nodes/{id}/stack/pages`: cria uma página em branco e a vira para a frente.
  /// Retorna o id do nó da nova página.
  Future<String> addStackPage({
    required String workspaceId,
    required String stackNodeId,
    String? afterNoteId,
  }) async {
    final json = await _notesWrite(
      'POST',
      '/api/workspaces/$workspaceId/nodes/$stackNodeId/stack/pages',
      {if (afterNoteId != null) 'afterNoteId': afterNoteId},
      'stack/pages POST',
    );
    return json['nodeId'] as String;
  }

  /// `DELETE …/nodes/{id}/stack/pages/{noteId}`: arquiva a página, que volta ao canvas.
  /// Com `x`/`y` a nota volta nessa posição do canvas.
  Future<NoteStackRail> archiveStackPage({
    required String workspaceId,
    required String stackNodeId,
    required String noteId,
    double? x,
    double? y,
  }) async {
    final json = await _notesWrite(
      'DELETE',
      '/api/workspaces/$workspaceId/nodes/$stackNodeId/stack/pages/$noteId',
      {if (x != null) 'x': x, if (y != null) 'y': y},
      'stack/pages DELETE',
    );
    return NoteStackRail.fromJson(json);
  }

  /// `PUT …/nodes/{id}/stack/pages/{noteId}`: arquiva uma nota solta no fichário,
  /// ou traz para cá uma página de outro fichário.
  Future<NoteStackRail> bringStackPage({
    required String workspaceId,
    required String stackNodeId,
    required String noteId,
  }) async {
    final json = await _notesWrite(
      'PUT',
      '/api/workspaces/$workspaceId/nodes/$stackNodeId/stack/pages/$noteId',
      const {},
      'stack/pages PUT',
    );
    return NoteStackRail.fromJson(json);
  }

  /// `POST …/note-stacks`: junta uma seleção de notas num fichário.
  /// Retorna o id do nó `noteStack` criado.
  Future<String> createNoteStack({
    required String workspaceId,
    required List<String> nodeIds,
    String? floorId,
  }) async {
    final json = await _notesWrite(
      'POST',
      '/api/workspaces/$workspaceId/note-stacks',
      {'nodeIds': nodeIds, if (floorId != null) 'floorId': floorId},
      'note-stacks',
    );
    return json['stackNodeId'] as String;
  }

  /// `PUT …/nodes/{id}/note/color`: retorna o `NoteContent` atualizado.
  Future<NoteContent> setNoteColor({
    required String workspaceId,
    required String nodeId,
    required String color,
    String? customColor,
  }) async {
    final json = await _notesWrite(
      'PUT',
      '/api/workspaces/$workspaceId/nodes/$nodeId/note/color',
      {'color': color, if (customColor != null) 'customColor': customColor},
      'note/color',
    );
    return NoteContent.fromJson(json);
  }

  /// `POST …/nodes/{id}/rename`: 400 não renomeável, 409 nota externa.
  Future<void> renameNode({
    required String workspaceId,
    required String nodeId,
    required String name,
  }) async {
    await _notesWrite(
      'POST',
      '/api/workspaces/$workspaceId/nodes/$nodeId/rename',
      {'name': name},
      'rename',
    );
  }

  /// `PUT …/nodes/{id}/note/lock`: liga ou desliga a trava de conteúdo da nota.
  /// Idempotente (é o estado desejado). `404` vira `HttpException`.
  Future<void> setContentLocked({
    required String workspaceId,
    required String nodeId,
    required bool locked,
  }) async {
    await _notesWrite(
      'PUT',
      '/api/workspaces/$workspaceId/nodes/$nodeId/note/lock',
      {'locked': locked},
      'note/lock',
    );
  }

  /// Notas que podem entrar num fichário: `items` do feed (`kind: note`), inclusive as
  /// arquivadas em outros fichários. `exclude` tira as que já estão no fichário aberto.
  Future<List<NoteCandidate>> loadNoteCandidates({
    required String workspaceId,
    Set<String> exclude = const {},
  }) async {
    final feed = await getJson('/api/workspaces/$workspaceId/feed');
    final items = feed['items'];
    if (items is! List) return const [];
    final out = <NoteCandidate>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final c = NoteCandidate.fromFeedItem(item);
      if (c != null && !exclude.contains(c.nodeId)) out.add(c);
    }
    return out;
  }

  /// Envia uma escrita de nota/fichário e decodifica `{ok, ...}`.
  /// Qualquer status diferente de 200 vira `HttpException` com o corpo do host.
  Future<Map<String, dynamic>> _notesWrite(
    String method,
    String path,
    Object body,
    String label,
  ) async {
    final res = await sendJson(method, path, body);
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('$label respondeu ${res.statusCode}: $text');
    }
    if (text.trim().isEmpty) return const {};
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw HttpException('$label devolveu um corpo inesperado: $text');
    }
    return decoded;
  }
}
