import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'wire_client.dart';

/// Gerenciador do Stream de Terminal PTY em tempo real.
/// Recebe saída ANSI crua do servidor e envia digitação / comandos do usuário.
class TerminalStream {
  final WireClient client;
  final String terminalId;
  WebSocket? _socket;
  StreamSubscription? _subscription;
  bool _isConnected = false;

  final StreamController<String> _textOutputController =
      StreamController<String>.broadcast();

  Stream<String> get output => _textOutputController.stream;
  bool get isConnected => _isConnected;

  TerminalStream({required this.client, required this.terminalId});

  Future<void> connect() async {
    disconnect();

    final pair = client.currentPairData;
    final token = client.authToken;
    if (pair == null || token == null) {
      throw Exception('Credenciais não disponíveis');
    }

    final uri = Uri(
      scheme: 'wss',
      host: pair.host,
      port: pair.port,
      path: '/api/terminals/$terminalId/stream',
      queryParameters: {'token': token},
    );

    final customHttpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    _socket = await WebSocket.connect(
      uri.toString(),
      customClient: customHttpClient,
    );

    _isConnected = true;

    _subscription = _socket!.listen(
      (data) {
        String? text;
        if (data is String) {
          // Ignora mensagens de controle interno como {"type":"geometry", ...}
          if (data.trim().startsWith('{"type":')) {
            return;
          }
          text = data;
        } else if (data is List<int>) {
          text = utf8.decode(data, allowMalformed: true);
        }

        if (text != null && text.isNotEmpty) {
          // Limpa sequências de escape ANSI cruas (CSI, OSC, etc.) e caracteres de controle
          final clean = text
              .replaceAll(RegExp(r'\x1B\][^\x07\x1B]*[\x07\x1B\\]'), '')
              .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
              .replaceAll(RegExp(r'\x1B[@-Z\\-_]'), '')
              .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
          if (clean.isNotEmpty) {
            _textOutputController.add(clean);
          }
        }
      },
      onError: (e) => _isConnected = false,
      onDone: () => _isConnected = false,
    );
  }

  /// Envia texto ou comandos digitados pelo usuário para o terminal remoto via frame binário
  void sendInput(String text) {
    if (_isConnected && _socket != null) {
      _socket!.add(utf8.encode(text));
    }
  }

  /// Envia comando de redimensionamento do terminal para o tamanho da tela do celular/computador
  void sendResize({required int cols, required int rows}) {
    if (_isConnected && _socket != null) {
      _socket!.add(jsonEncode({
        'type': 'resize',
        'cols': cols,
        'rows': rows,
      }));
    }
  }

  void disconnect() {
    _subscription?.cancel();
    _socket?.close();
    _subscription = null;
    _socket = null;
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _textOutputController.close();
  }
}
