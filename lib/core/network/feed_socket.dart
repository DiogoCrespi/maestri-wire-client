import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'wire_client.dart';

/// Gerenciador do Feed WebSocket em tempo real.
/// Mantém o canvas do celular/computador sincronizado com o host em tempo real.
class FeedSocket {
  final WireClient client;
  WebSocket? _socket;
  StreamSubscription? _subscription;
  bool _isConnected = false;

  final StreamController<Map<String, dynamic>> _rawUpdatesController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get updates => _rawUpdatesController.stream;
  bool get isConnected => _isConnected;

  FeedSocket({required this.client});

  Timer? _pingTimer;
  Timer? _reconnectTimer;
  String? _lastWorkspaceId;
  String? _lastFloorId;

  /// Conecta ao feed WebSocket do workspace e andar especificados.
  Future<void> connect({required String workspaceId, String? floorId}) async {
    _lastWorkspaceId = workspaceId;
    _lastFloorId = floorId;
    disconnect();

    final pair = client.currentPairData;
    final token = client.authToken;
    if (pair == null || token == null) {
      throw Exception('Credenciais não disponíveis para conectar ao Feed');
    }

    final queryParams = {
      'ws': workspaceId,
      'token': token,
      if (floorId != null && floorId.isNotEmpty) 'floor': floorId,
    };

    final uri = Uri(
      scheme: 'wss',
      host: pair.host,
      port: pair.port,
      path: '/api/feed/stream',
      queryParameters: queryParams,
    );

    try {
      final customHttpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      _socket = await WebSocket.connect(
        uri.toString(),
        customClient: customHttpClient,
      );

      _isConnected = true;

      // Heartbeat a cada 15s para manter a conexão WebSocket viva
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_isConnected && _socket != null) {
          try {
            _socket!.add(jsonEncode({'type': 'ping'}));
          } catch (_) {}
        }
      });

      _subscription = _socket!.listen(
        (data) {
          try {
            if (data is String) {
              final Map<String, dynamic> json = jsonDecode(data);
              _rawUpdatesController.add(json);
            }
          } catch (e) {
            // Ignora frames malformados
          }
        },
        onError: (err) {
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _isConnected = false;
      _scheduleReconnect();
      rethrow;
    }
  }

  void _scheduleReconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_isConnected && _lastWorkspaceId != null) {
        connect(workspaceId: _lastWorkspaceId!, floorId: _lastFloorId)
            .catchError((_) {});
      }
    });
  }

  /// Envia comando de foco de nó ou atualização
  void sendJson(Map<String, dynamic> message) {
    if (_isConnected && _socket != null) {
      _socket!.add(jsonEncode(message));
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _socket?.close();
    _subscription = null;
    _socket = null;
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _rawUpdatesController.close();
  }
}
