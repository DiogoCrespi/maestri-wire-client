import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/network/wire_client.dart';
import '../core/network/feed_socket.dart';
import '../models/pair_data.dart';
import '../models/workspace.dart';
import '../models/canvas_node.dart';
import '../models/cable_tie.dart';

enum ConnectionStatus {
  unpaired,
  connecting,
  connected,
  error,
}

class WireController extends ChangeNotifier {
  final WireClient client = WireClient();
  late final FeedSocket feedSocket;

  ConnectionStatus status = ConnectionStatus.unpaired;
  String? errorMessage;
  String? hostName;

  List<WorkspaceMeta> workspaces = [];
  WorkspaceMeta? activeWorkspace;
  FloorMeta? activeFloor;

  List<CanvasNode> nodes = [];
  List<CableTie> cables = [];

  StreamSubscription? _feedSubscription;
  Timer? _pollingTimer;

  WireController() {
    feedSocket = FeedSocket(client: client);
    _init();
  }

  Future<void> _init() async {
    final hasCredentials = await client.loadSavedCredentials();
    if (hasCredentials) {
      await connectToHost();
    }
  }

  /// Conecta e sincroniza dados com o Host
  Future<void> connectToHost() async {
    status = ConnectionStatus.connecting;
    errorMessage = null;
    notifyListeners();

    try {
      final info = await client.getInfo();
      hostName = info['name'] ?? 'Maestri Host';

      workspaces = await client.getWorkspaces();
      if (workspaces.isNotEmpty) {
        activeWorkspace = workspaces.first;
        try {
          final snapshot = await client.getWorkspaceFeed(activeWorkspace!.id);
          _handleFeedUpdate(snapshot);
        } catch (_) {}
        await _subscribeFeed();
        _startPolling();
      }

      status = ConnectionStatus.connected;
      notifyListeners();
    } catch (e) {
      status = ConnectionStatus.error;
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (status == ConnectionStatus.connected && activeWorkspace != null) {
        refreshFeed();
      }
    });
  }

  /// Realiza o pareamento a partir do QR code ou formulário manual
  Future<bool> pairWithHost({
    required PairData pairData,
    required String deviceName,
    String? code,
    String? password,
  }) async {
    status = ConnectionStatus.connecting;
    errorMessage = null;
    notifyListeners();

    try {
      await client.pair(
        pairData: pairData,
        deviceName: deviceName,
        code: code,
        password: password,
      );

      await connectToHost();
      return true;
    } catch (e) {
      status = ConnectionStatus.unpaired;
      errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('HttpException: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Alterna o workspace ativo e reconecta o feed
  Future<void> selectWorkspace(WorkspaceMeta ws) async {
    activeWorkspace = ws;
    notifyListeners();
    await _subscribeFeed();
    await refreshFeed();
  }

  /// Consulta ativa e atualização manual do feed do workspace
  Future<void> refreshFeed() async {
    if (activeWorkspace == null || client.authToken == null) return;
    try {
      final snapshot = await client.getWorkspaceFeed(activeWorkspace!.id);
      _handleFeedUpdate(snapshot);
    } catch (_) {}
  }

  Future<void> _subscribeFeed() async {
    if (activeWorkspace == null) return;

    try {
      await feedSocket.connect(
        workspaceId: activeWorkspace!.id,
        floorId: activeFloor?.id,
      );

      _feedSubscription?.cancel();
      _feedSubscription = feedSocket.updates.listen((data) {
        _handleFeedUpdate(data);
      });
    } catch (e) {
      // Ignora erro passageiro de websocket
    }
  }

  void _handleFeedUpdate(Map<String, dynamic> data) {
    // Se a mensagem contiver mutations ou diffs, aciona um refresh completo
    if (data['type'] == 'mutation' ||
        data.containsKey('mutation') ||
        data['type'] == 'diff') {
      refreshFeed();
      return;
    }

    // Desenvelopa o payload: WebSocket encapsula em 'snapshot', enquanto GET HTTP entrega direto
    final feedPayload = (data['snapshot'] as Map<String, dynamic>?) ??
        (data.containsKey('canvas') ? data : null);

    if (feedPayload != null && feedPayload.containsKey('canvas')) {
      final canvasData = feedPayload['canvas'] as Map<String, dynamic>;
      
      // Parse de Nós
      if (canvasData.containsKey('nodes')) {
        final List<dynamic> nodeList = canvasData['nodes'];
        nodes = nodeList.map((e) => CanvasNode.fromJson(e)).toList();
      }

      // Parse de Conexões / Cabos
      if (canvasData.containsKey('connections') ||
          canvasData.containsKey('cables') ||
          canvasData.containsKey('cableTies') ||
          canvasData.containsKey('ties')) {
        final List<dynamic> cableList = canvasData['connections'] ??
            canvasData['cables'] ??
            canvasData['cableTies'] ??
            canvasData['ties'] ??
            [];
        cables = cableList.map((e) => CableTie.fromJson(e)).toList();
      }

      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _feedSubscription?.cancel();
    feedSocket.dispose();
    super.dispose();
  }
}
