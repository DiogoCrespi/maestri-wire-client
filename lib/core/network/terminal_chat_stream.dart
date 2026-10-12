import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/terminal_chat.dart';
import 'tls_pinning.dart';
import 'wire_client.dart';

/// Socket do chat de um terminal: WSS /api/terminals/{id}/chat/stream?token=…
///
/// Cada frame `{"type":"chat","snapshot":…}` substitui a cauda inteira; nunca é
/// mesclado como acréscimo. Reconectar entrega uma cauda completa de novo.
class TerminalChatStream {
  final WireClient client;
  final String terminalId;

  final StreamController<ChatSnapshot> _controller =
      StreamController<ChatSnapshot>.broadcast();
  WebSocket? _socket;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;

  TerminalChatStream({required this.client, required this.terminalId});

  Stream<ChatSnapshot> get snapshots => _controller.stream;

  Future<void> connect() async {
    _disposed = false;
    final pair = client.currentPairData;
    final token = client.authToken;
    if (pair == null || token == null) return;

    final uri = Uri(
      scheme: 'wss',
      host: pair.host,
      port: pair.port,
      path: '/api/terminals/$terminalId/chat/stream',
      queryParameters: {'token': token},
    );

    try {
      final http = createPinnedHttpClient(expectedPin: pair.serverKeyHash);
      _socket = await WebSocket.connect(uri.toString(), customClient: http);
    } catch (_) {
      _scheduleReconnect();
      return;
    }

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _socket?.add(jsonEncode({'type': 'ping'}));
    });

    _socket!.listen(
      (data) {
        if (data is! String) return;
        try {
          final msg = jsonDecode(data) as Map<String, dynamic>;
          // Tipos desconhecidos e `pong` são ignorados, como o contrato pede
          if (msg['type'] == 'chat' && msg['snapshot'] is Map<String, dynamic>) {
            _controller.add(ChatSnapshot.fromJson(msg['snapshot'] as Map<String, dynamic>));
          }
        } catch (_) {
          // Frame malformado não derruba o socket
        }
      },
      onDone: _scheduleReconnect,
      onError: (_) => _scheduleReconnect(),
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    _pingTimer?.cancel();
    _socket = null;
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), connect);
  }

  void disconnect() {
    _disposed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
