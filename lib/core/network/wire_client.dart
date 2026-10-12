import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../models/pair_data.dart';
import '../../models/workspace.dart';
import '../../models/note_content.dart';
import 'tls_pinning.dart';

class PortalSnapshot {
  final List<int> bytes;
  final String? etag;
  final String? contentType;

  const PortalSnapshot({required this.bytes, this.etag, this.contentType});
}

/// Cliente HTTP para a API Maestri Wire.
/// Implementa TLS Certificate Pinning (verificação de SHA-256 SPKI),
/// headers obrigatórios do protocolo e autenticação Bearer Token.
class WireClient {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  
  PairData? currentPairData;
  String? authToken;
  String? deviceId;

  WireClient({this.currentPairData, this.authToken, this.deviceId});

  /// Inicializa o cliente carregando credenciais salvas no armazenamento seguro.
  Future<bool> loadSavedCredentials() async {
    final token = await _storage.read(key: 'wire_token');
    final host = await _storage.read(key: 'wire_host');
    final portStr = await _storage.read(key: 'wire_port');
    final keyHash = await _storage.read(key: 'wire_key_hash');

    if (token != null && host != null && portStr != null) {
      authToken = token;
      currentPairData = PairData(
        protocolVersion: 1,
        scheme: 'https',
        host: host,
        port: int.tryParse(portStr) ?? 7434,
        serverKeyHash: keyHash ?? '',
      );
      return true;
    }
    return false;
  }

  /// Salva as credenciais persistentes no dispositivo.
  Future<void> saveCredentials(PairResponse res, PairData pair) async {
    authToken = res.token;
    deviceId = res.deviceId;
    currentPairData = pair;

    await _storage.write(key: 'wire_token', value: res.token);
    await _storage.write(key: 'wire_device_id', value: res.deviceId);
    await _storage.write(key: 'wire_host', value: pair.host);
    await _storage.write(key: 'wire_port', value: pair.port.toString());
    await _storage.write(key: 'wire_key_hash', value: pair.serverKeyHash);
  }

  /// Cria um HttpClient com TLS Pinning do serverKeyHash salvo
  HttpClient _createSecureHttpClient() {
    final client = createPinnedHttpClient(expectedPin: currentPairData?.serverKeyHash);
    client.connectionTimeout = const Duration(seconds: 10);
    return client;
  }

  /// Rota de Pareamento: POST /pair
  Future<PairResponse> pair({
    required PairData pairData,
    required String deviceName,
    String? code,
    String? password,
  }) async {
    // Pareamento manual não tem hash: o certificado visto aqui é fixado (TOFU).
    String? observedPin;
    final client = createPinnedHttpClient(
      expectedPin: pairData.serverKeyHash,
      onObserved: (pin) => observedPin = pin,
    );
    client.connectionTimeout = const Duration(seconds: 10);

    // Prioriza Tailscale (100.x) ou o host informado, seguido de alternateHosts
    final hostsToTry = <String>[];
    if (pairData.host.startsWith('100.')) {
      hostsToTry.add(pairData.host);
    }
    for (final h in pairData.alternateHosts) {
      if (h.startsWith('100.') && !hostsToTry.contains(h)) {
        hostsToTry.add(h);
      }
    }
    if (!hostsToTry.contains(pairData.host)) {
      hostsToTry.add(pairData.host);
    }
    for (final h in pairData.alternateHosts) {
      if (!hostsToTry.contains(h)) {
        hostsToTry.add(h);
      }
    }

    String? lastError;

    for (final candidateHost in hostsToTry) {
      try {
        final uri = Uri.parse('${pairData.scheme}://$candidateHost:${pairData.port}/pair');
        observedPin = null;
        final request = await client.postUrl(uri).timeout(const Duration(seconds: 4));
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(
            HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
        request.headers.set(HttpHeaders.connectionHeader, 'close');
        request.headers.set(HttpHeaders.hostHeader, candidateHost);

        final payload = <String, dynamic>{
          'deviceName': deviceName,
        };
        // O protocolo Maestri Wire exige EXATAMENTE UM entre code ou password
        if (password != null && password.isNotEmpty) {
          payload['password'] = password;
        } else if (code != null && code.isNotEmpty) {
          payload['code'] = code;
        }

        request.add(utf8.encode(jsonEncode(payload)));
        final response =
            await request.close().timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final Map<String, dynamic> json = jsonDecode(responseBody);
          final pairRes = PairResponse.fromJson(json);
          final updatedPair = pairData.copyWith(
            host: candidateHost,
            serverKeyHash: pairData.serverKeyHash.isEmpty ? observedPin : null,
          );
          await saveCredentials(pairRes, updatedPair);
          return pairRes;
        } else if (response.statusCode == 401) {
          throw const HttpException('Código de 6 dígitos ou senha incorretos.');
        } else if (response.statusCode == 429) {
          throw const HttpException('Muitas tentativas. Aguarde 30 segundos.');
        } else if (response.statusCode == 503) {
          throw const HttpException('Pareamento por senha não habilitado no host Linux.');
        } else {
          final errBody = await response.transform(utf8.decoder).join();
          lastError = 'Host recusou (${response.statusCode}): $errBody';
        }
      } catch (e) {
        if (e is HttpException) rethrow;
        lastError = 'Não foi possível conectar em $candidateHost ($e)';
      }
    }

    throw HttpException(lastError ?? 'Não foi possível conectar ao servidor Linux. Verifique se o Maestri Wire está ativo.');
  }

  /// Consulta Snapshot do Workspace: GET /api/workspaces/{id}/feed
  Future<Map<String, dynamic>> getWorkspaceFeed(String workspaceId) async {
    if (currentPairData == null) throw Exception('Host não configurado');
    final client = _createSecureHttpClient();
    final uri = Uri.parse('${currentPairData!.baseUrl}/api/workspaces/$workspaceId/feed');

    final request = await client.getUrl(uri);
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    return jsonDecode(responseBody);
  }

  /// Consulta Informações do Host: GET /api/info
  Future<Map<String, dynamic>> getInfo() async {
    if (currentPairData == null) throw Exception('Host não configurado');
    final client = _createSecureHttpClient();
    final uri = Uri.parse('${currentPairData!.baseUrl}/api/info');

    final request = await client.getUrl(uri);
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    return jsonDecode(responseBody);
  }

  /// Lista Workspaces: GET /api/workspaces
  Future<List<WorkspaceMeta>> getWorkspaces() async {
    if (currentPairData == null) throw Exception('Host não configurado');
    final client = _createSecureHttpClient();
    final uri = Uri.parse('${currentPairData!.baseUrl}/api/workspaces');

    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    final Map<String, dynamic> data = jsonDecode(responseBody);

    final List<dynamic> list = data['workspaces'] ?? [];
    return list.map((e) => WorkspaceMeta.fromJson(e)).toList();
  }

  /// Envia um Prompt para um Terminal/Agente: POST /api/terminals/{id}/prompt
  /// Snapshot do chat do terminal: GET /api/terminals/{id}/chat (capability `terminalChat`)
  Future<Map<String, dynamic>> getTerminalChat(String terminalId) async {
    final body = await _getJson('/api/terminals/$terminalId/chat');
    return body;
  }

  /// Pede a página anterior à entrada mais antiga da cauda. As entradas chegam
  /// no próximo snapshot do socket de chat, não nesta resposta.
  Future<bool> requestOlderChat({
    required String terminalId,
    required String conversationId,
    required String beforeEntryId,
  }) async {
    final res = await _sendJson(
      'POST',
      '/api/terminals/$terminalId/chat/history',
      {'conversationId': conversationId, 'beforeEntryId': beforeEntryId},
    );
    return res.statusCode == 200;
  }

  /// Imagem atual do portal (JPEG/PNG). Retorna null quando não há imagem
  /// (503 "not rendering", 404) ou quando o ETag ainda é o mesmo (304).
  Future<PortalSnapshot?> getPortalSnapshot(String portalId, {String? etag}) async {
    if (currentPairData == null) throw Exception('Host não configurado');
    final client = _createSecureHttpClient();
    final uri = Uri.parse('${currentPairData!.baseUrl}/api/portals/$portalId/snapshot');
    final request = await client.getUrl(uri);
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');
    if (etag != null) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    }
    final response = await request.close();
    if (response.statusCode == 304 || response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return PortalSnapshot(
      bytes: builder.takeBytes(),
      etag: response.headers.value(HttpHeaders.etagHeader),
      contentType: response.headers.contentType?.mimeType,
    );
  }

  /// Revela um nó no canvas do host (capability `nodeFocus`). Escrita: só owner.
  Future<bool> focusNode({required String workspaceId, required String nodeId}) async {
    final res = await _sendJson(
      'POST',
      '/api/workspaces/$workspaceId/nodes/$nodeId/focus',
      null,
    );
    return res.statusCode == 200;
  }

  /// API pública para camadas de feature (ver lib/core/network/api_*.dart).
  /// GET autenticado que devolve um objeto JSON; lança em status diferente de 200.
  Future<Map<String, dynamic>> getJson(String path) => _getJson(path);

  /// Requisição JSON autenticada. O chamador lê o corpo da resposta.
  Future<HttpClientResponse> sendJson(String method, String path, [Object? body]) =>
      _sendJson(method, path, body);

  Future<Map<String, dynamic>> _getJson(String path) async {
    if (currentPairData == null) throw Exception('Host não configurado');
    final client = _createSecureHttpClient();
    final request = await client.getUrl(Uri.parse('${currentPairData!.baseUrl}$path'));
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('GET $path respondeu ${response.statusCode}: $text');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<HttpClientResponse> _sendJson(String method, String path, Object? body) async {
    if (currentPairData == null) throw Exception('Host não configurado');
    final client = _createSecureHttpClient();
    final request = await client.openUrl(method, Uri.parse('${currentPairData!.baseUrl}$path'));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');
    request.add(utf8.encode(jsonEncode(body ?? {})));
    return request.close();
  }

  /// Conteúdo da nota (capability `nativeNotes`)
  Future<NoteContent> getNote({required String workspaceId, required String nodeId}) async {
    final json = await _getJson('/api/workspaces/$workspaceId/nodes/$nodeId/note');
    return NoteContent.fromJson(json);
  }

  /// Grava a nota. Com `ifRevision`, 412 devolve a versão atual para resolver o conflito.
  Future<NoteSaveResult> putNote({
    required String workspaceId,
    required String nodeId,
    required String text,
    String? ifRevision,
  }) async {
    final res = await _sendJson(
      'PUT',
      '/api/workspaces/$workspaceId/nodes/$nodeId/note',
      {'text': text, if (ifRevision != null) 'ifRevision': ifRevision},
    );
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 200) {
      return NoteSaveResult(
        saved: true,
        current: NoteContent.fromJson(jsonDecode(body) as Map<String, dynamic>),
      );
    }
    if (res.statusCode == 412) {
      return NoteSaveResult(
        saved: false,
        conflict: true,
        current: NoteContent.fromJson(jsonDecode(body) as Map<String, dynamic>),
      );
    }
    if (res.statusCode == 409) {
      return const NoteSaveResult(saved: false, locked: true);
    }
    throw HttpException('PUT note respondeu ${res.statusCode}: $body');
  }

  /// Cria uma nota no canvas do workspace. Retorna o id do nó criado.
  Future<String> createNote({
    required String workspaceId,
    required double x,
    required double y,
    String text = '',
  }) async {
    final res = await _sendJson(
      'POST',
      '/api/workspaces/$workspaceId/nodes',
      {'kind': 'note', 'x': x, 'y': y, 'text': text},
    );
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('POST nodes respondeu ${res.statusCode}: $body');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['nodeId'] as String;
  }

  /// Trava ou destrava o conteúdo da nota (idempotente: é o estado desejado)
  Future<bool> setNoteLocked({
    required String workspaceId,
    required String nodeId,
    required bool locked,
  }) async {
    final res = await _sendJson(
      'PUT',
      '/api/workspaces/$workspaceId/nodes/$nodeId/note/lock',
      {'locked': locked},
    );
    await res.drain<void>();
    return res.statusCode == 200;
  }

  /// Remove um nó do canvas (escrita, owner)
  Future<bool> deleteNode({required String workspaceId, required String nodeId}) async {
    if (currentPairData == null) throw Exception('Host não configurado');
    final client = _createSecureHttpClient();
    final request = await client.openUrl(
      'DELETE',
      Uri.parse('${currentPairData!.baseUrl}/api/workspaces/$workspaceId/nodes/$nodeId'),
    );
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode == 200;
  }

  Future<bool> sendPrompt({
    required String terminalId,
    required String prompt,
    String? workspaceId,
  }) async {
    if (currentPairData == null) throw Exception('Host não configurado');
    final client = _createSecureHttpClient();
    final uri = Uri.parse('${currentPairData!.baseUrl}/api/terminals/$terminalId/prompt');

    final request = await client.postUrl(uri);
    request.headers.set(
        HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');

    request.add(utf8.encode(jsonEncode({'text': prompt})));
    final response = await request.close();
    return response.statusCode == 200;
  }

  /// Aprova a ação pendente de um agente: POST /api/terminals/{id}/approve
  Future<bool> approveTerminal(String terminalId) async {
    if (currentPairData == null) return false;
    final client = _createSecureHttpClient();
    final uri = Uri.parse('${currentPairData!.baseUrl}/api/terminals/$terminalId/approve');

    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');

    request.write('{}');
    final response = await request.close();
    return response.statusCode == 200;
  }

  /// Rejeita a ação pendente de um agente: POST /api/terminals/{id}/reject
  Future<bool> rejectTerminal(String terminalId) async {
    if (currentPairData == null) return false;
    final client = _createSecureHttpClient();
    final uri = Uri.parse('${currentPairData!.baseUrl}/api/terminals/$terminalId/reject');

    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');

    request.write('{}');
    final response = await request.close();
    return response.statusCode == 200;
  }

  /// Recarrega um portal web: POST /api/portals/{id}/reload
  Future<bool> reloadPortal(String portalId) async {
    if (currentPairData == null) return false;
    final client = _createSecureHttpClient();
    final uri = Uri.parse('${currentPairData!.baseUrl}/api/portals/$portalId/reload');

    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');

    request.write('{}');
    final response = await request.close();
    return response.statusCode == 200;
  }

  /// Navega para trás no portal web: POST /api/portals/{id}/back
  Future<bool> backPortal(String portalId) async {
    if (currentPairData == null) return false;
    final client = _createSecureHttpClient();
    final uri = Uri.parse('${currentPairData!.baseUrl}/api/portals/$portalId/back');

    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');

    request.write('{}');
    final response = await request.close();
    return response.statusCode == 200;
  }

  /// Navega para frente no portal web: POST /api/portals/{id}/forward
  Future<bool> forwardPortal(String portalId) async {
    if (currentPairData == null) return false;
    final client = _createSecureHttpClient();
    final uri = Uri.parse('${currentPairData!.baseUrl}/api/portals/$portalId/forward');

    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (authToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    request.headers.set(HttpHeaders.hostHeader, currentPairData!.host);
    request.headers.set(HttpHeaders.connectionHeader, 'close');

    request.write('{}');
    final response = await request.close();
    return response.statusCode == 200;
  }
}
