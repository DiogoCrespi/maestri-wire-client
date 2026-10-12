import 'dart:convert';
import 'dart:io';

import '../../models/chat_attachment.dart';
import '../../models/chat_mention.dart';
import '../../models/terminal_chat.dart';
import 'api_terminal_actions.dart';
import 'tls_pinning.dart';
import 'wire_client.dart';

/// Chat do terminal (capability `terminalChat`), anexos, menções e arquivos para `@`
/// (`terminalFileMentions`). Escritas exigem owner no host. Resposta não-2xx vira
/// [TerminalActionException] com a mensagem do host.
///
/// Os alvos resolvem no térreo e nos andares sem ativar o workspace do host.
extension ChatApi on WireClient {
  String _tp(String terminalId, [String rest = '']) =>
      '/api/terminals/${Uri.encodeComponent(terminalId)}$rest';

  /// PUT …/chat `{enabled, showsShellWindow?}`. Com `showsShellWindow` a face não muda.
  Future<ChatSnapshot> setChatEnabled(
    String terminalId, {
    required bool enabled,
    bool? showsShellWindow,
  }) async {
    final json = await _chatJson('PUT', _tp(terminalId, '/chat'), {
      'enabled': enabled,
      if (showsShellWindow != null) 'showsShellWindow': showsShellWindow,
    });
    return ChatSnapshot.fromJson(json);
  }

  /// PUT …/chat/thread `{slot}`: seleciona um dos slots 0…6.
  Future<ChatSnapshot> selectChatThread(String terminalId, int slot) async {
    final json = await _chatJson('PUT', _tp(terminalId, '/chat/thread'), {'slot': slot});
    return ChatSnapshot.fromJson(json);
  }

  /// DELETE …/chat/thread `{slot}`: limpa o slot sem selecioná-lo.
  Future<void> clearChatThread(String terminalId, int slot) =>
      _chatJson('DELETE', _tp(terminalId, '/chat/thread'), {'slot': slot});

  /// POST …/attachments?filename= com corpo cru. Staging: vale 15 min, até 8 MiB.
  Future<ChatAttachment> uploadChatAttachment(
    String terminalId, {
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final path = _tp(terminalId, '/attachments?filename=${Uri.encodeComponent(fileName)}');
    final json = await _rawChatRequest('POST', path, bytes, mimeType);
    return ChatAttachment.fromJson(json);
  }

  /// DELETE …/attachments/{id}: tira um anexo preparado antes do envio.
  Future<void> discardStagedAttachment(String terminalId, String attachmentId) =>
      _chatJson('DELETE', _tp(terminalId, '/attachments/${Uri.encodeComponent(attachmentId)}'));

  /// POST …/prompt com `{segments}`. `clientMessageId` é metadado de apresentação,
  /// não idempotência: nunca repita um envio ambíguo automaticamente.
  Future<void> sendChatPrompt(
    String terminalId,
    List<PromptSegment> segments, {
    String? clientMessageId,
  }) =>
      _chatJson('POST', _tp(terminalId, '/prompt'), {
        'segments': [for (final s in segments) s.toJson()],
        if (clientMessageId != null) 'clientMessageId': clientMessageId,
      });

  /// POST …/chat/read: marca as mensagens do chat como lidas.
  Future<void> markChatRead(String terminalId) => _chatJson('POST', _tp(terminalId, '/chat/read'));

  /// DELETE …/chat/entries/{entryId}: exclui uma entrada durável.
  Future<void> deleteChatEntry(String terminalId, String entryId) =>
      _chatJson('DELETE', _tp(terminalId, '/chat/entries/${Uri.encodeComponent(entryId)}'));

  /// DELETE …/chat/history: limpa a transcrição (não a memória do provedor).
  /// `409` enquanto um turno ou importação impede.
  Future<void> clearChatHistory(String terminalId) => _chatJson('DELETE', _tp(terminalId, '/chat/history'));

  /// DELETE …/chat/attachments/{id}: remove um anexo já retido numa conversa.
  Future<void> deleteRetainedAttachment(String terminalId, String attachmentId) => _chatJson(
      'DELETE', _tp(terminalId, '/chat/attachments/${Uri.encodeComponent(attachmentId)}'));

  /// GET …/mentions: alvos para o seletor de `@`.
  Future<List<ChatMention>> getChatMentions(String terminalId) async {
    final json = await getJson(_tp(terminalId, '/mentions'));
    return ChatMention.listFromJson(json);
  }

  /// GET …/files: índice de arquivos do compositor do host (owner).
  /// `scope` é uma pasta relativa ao diretório do terminal ('' para o topo);
  /// `query` filtra dentro dela. `limit` no máximo 200.
  Future<ChatFileListing> getTerminalFiles(
    String terminalId, {
    String query = '',
    String scope = '',
    int limit = 100,
  }) async {
    final path = _tp(
      terminalId,
      '/files?query=${Uri.encodeComponent(query)}'
      '&scope=${Uri.encodeComponent(scope)}&limit=${limit.clamp(1, 200)}',
    );
    return ChatFileListing.fromJson(await getJson(path));
  }

  /// POST …/seen: limpa a atenção do terminal, como clicar nele no host.
  Future<void> markTerminalSeen(String terminalId) => _chatJson('POST', _tp(terminalId, '/seen'));

  Future<Map<String, dynamic>> _chatJson(String method, String path, [Object? body]) {
    final bytes = utf8.encode(jsonEncode(body ?? const <String, dynamic>{}));
    return _rawChatRequest(method, path, bytes, 'application/json; charset=utf-8');
  }

  /// Requisição autenticada com corpo cru. Mesmo TLS pinning, Host e token das
  /// outras chamadas do cliente. Devolve o JSON decodificado (ou `{}` sem corpo).
  Future<Map<String, dynamic>> _rawChatRequest(
    String method,
    String path,
    List<int> bytes,
    String contentType,
  ) async {
    final pair = currentPairData;
    if (pair == null) throw Exception('Host não configurado');
    final http = createPinnedHttpClient(expectedPin: pair.serverKeyHash);
    http.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await http.openUrl(method, Uri.parse('${pair.baseUrl}$path'));
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      if (authToken != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
      }
      request.headers.set(HttpHeaders.hostHeader, pair.host);
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      request.add(bytes);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw TerminalActionException.fromResponse(response.statusCode, text);
      }
      if (text.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } finally {
      http.close(force: true);
    }
  }
}
