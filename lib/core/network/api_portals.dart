import 'dart:convert';
import 'dart:io';

import 'wire_client.dart';

/// Ações de controle de portal (escrita). Snapshot continua em
/// `WireClient.getPortalSnapshot`. Contrato: "## Portais" em maestri-wire.md.
extension PortalsApi on WireClient {
  /// `POST /api/portals/{id}/reload`: recarrega, ou acorda um portal descarregado.
  Future<void> reloadPortal(String id) => _portalAction(id, 'reload');

  /// `POST /api/portals/{id}/back`
  Future<void> portalBack(String id) => _portalAction(id, 'back');

  /// `POST /api/portals/{id}/forward`
  Future<void> portalForward(String id) => _portalAction(id, 'forward');

  /// `POST /api/portals/{id}/navigate` com `{url}`. A URL é validada antes.
  Future<void> navigatePortal(String id, String url) => _expectOk(
        sendJson('POST', portalPath(id, 'navigate'),
            {'url': validatePortalUrl(url)}),
      );

  /// `POST /api/portals/{id}/unload`: o Descarregar do host.
  Future<void> unloadPortal(String id) => _portalAction(id, 'unload');

  Future<void> _portalAction(String id, String action) =>
      _expectOk(sendJson('POST', portalPath(id, action)));
}

/// Caminho `/api/portals/{id}/{action}` (sem barra final quando `action` é null).
String portalPath(String id, [String? action]) {
  final base = '/api/portals/${Uri.encodeComponent(id)}';
  return action == null ? base : '$base/$action';
}

/// Aceita só http e https com host. Devolve a URL aparada; lança [ArgumentError].
String validatePortalUrl(String raw) {
  final url = raw.trim();
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    throw ArgumentError('Informe uma URL http:// ou https:// completa.');
  }
  return url;
}

Future<void> _expectOk(Future<HttpClientResponse> pending) async {
  final response = await pending;
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(_errorMessage(response.statusCode, text));
  }
}

String _errorMessage(int status, String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['error'] is Map) {
      final err = decoded['error'] as Map;
      final message = err['message'] ?? err['code'];
      if (message != null) return '$message (HTTP $status)';
    }
  } catch (_) {
    // corpo não é JSON
  }
  return 'Host respondeu HTTP $status${text.isEmpty ? '' : ': $text'}';
}
