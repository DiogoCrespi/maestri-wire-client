import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'terminal_text.dart';
import 'tls_pinning.dart';
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

  // Um decodificador por conexão: mantém bytes parciais de caracteres UTF-8
  Utf8StreamDecoder _utf8 = Utf8StreamDecoder();

  final StreamController<({int rows, int cols})> _geometryController =
      StreamController<({int rows, int cols})>.broadcast();

  Stream<String> get output => _textOutputController.stream;

  /// Tamanho da tela da TUI no host (`{"type":"geometry", cols, rows}`).
  Stream<({int rows, int cols})> get geometry => _geometryController.stream;
  bool get isConnected => _isConnected;

  TerminalStream({required this.client, required this.terminalId});

  Future<void> connect() async {
    disconnect();
    _utf8 = Utf8StreamDecoder();

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

    final customHttpClient = createPinnedHttpClient(expectedPin: pair.serverKeyHash);

    _socket = await WebSocket.connect(
      uri.toString(),
      customClient: customHttpClient,
    );

    _isConnected = true;

    _subscription = _socket!.listen(
      (data) {
        if (data is String) {
          // Mensagens de controle internas: geometria vai para a tela, o resto é ignorado
          if (data.trim().startsWith('{"type":')) {
            _handleControl(data);
            return;
          }
          _textOutputController.add(data);
        } else if (data is List<int>) {
          // Decodificação UTF-8 com estado: um caractere cortado entre frames é preservado
          final text = _utf8.add(data);
          if (text.isNotEmpty) _textOutputController.add(text);
        }
      },
      onError: (e) => _isConnected = false,
      onDone: () => _isConnected = false,
    );
  }

  void _handleControl(String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      if (json['type'] == 'geometry') {
        _geometryController.add((
          rows: (json['rows'] as num).toInt(),
          cols: (json['cols'] as num).toInt(),
        ));
      }
    } catch (_) {
      // Controle malformado: não interrompe o stream
    }
  }

  /// Envia texto ou comandos digitados pelo usuário para o terminal remoto via frame binário
  void sendInput(String text) {
    if (_isConnected && _socket != null) {
      _socket!.add(utf8.encode(text));
    }
  }

  /// Envia teclas de controle (setas, Enter, Esc) como bytes, pelo canal `inputBytes`.
  void sendControl(String sequence) {
    if (_isConnected && _socket != null) {
      _socket!.add(jsonEncode({
        'type': 'inputBytes',
        'data': base64Encode(utf8.encode(sequence)),
      }));
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
    _geometryController.close();
  }
}
