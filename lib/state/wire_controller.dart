import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/network/wire_client.dart';
import '../core/network/feed_socket.dart';
import '../core/network/api_floors.dart';
import '../core/network/api_terminals.dart';
import '../core/network/api_workspaces.dart';
import '../core/network/api_pull_requests.dart';
import '../core/network/api_hooks.dart';
import '../models/agent_preset.dart';
import '../models/pair_data.dart';
import '../models/floor.dart';
import '../models/workspace.dart';
import '../models/sidebar_layout.dart';
import '../models/floor_hooks.dart';
import '../models/pull_request.dart';
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
  /// Pastas e grupos da barra lateral (vêm de GET /api/workspaces).
  SidebarLayout sidebarLayout = SidebarLayout.empty;
  WorkspaceMeta? activeWorkspace;
  FloorMeta? activeFloor;

  List<CanvasNode> nodes = [];
  List<CableTie> cables = [];
  /// Andares do workspace (vêm do feed). O térreo tem id null.
  List<FloorMeta> floors = [];
  /// Andar que o cliente está mostrando. null = o andar ativo do host.
  /// Trocar de andar aqui não ativa nada no host.
  FloorMeta? viewingFloor;
  /// Papel do dispositivo no host (owner pode escrever; guest é somente leitura).
  bool isOwner = true;
  /// Presets de agente do host, carregados uma vez ao conectar (o sheet de Novo Terminal abre na hora).
  List<AgentPreset> presets = [];
  /// Modo de roteamento dos cabos do workspace: avoidNodes, behindNodes ou circuit.
  /// Em `circuit`, os pontos do host podem estar desatualizados; desenhe das pontas.
  String ropeRouting = 'avoidNodes';

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
      isOwner = (info['role'] ?? 'owner') == 'owner';

      final listing = await client.listWorkspacesWithLayout();
      workspaces = listing.workspaces;
      sidebarLayout = listing.layout;
      try {
        presets = await client.listPresets();
      } catch (_) {
        // Sem presets o sheet tenta de novo ao abrir
      }
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
      final snapshot = await client.getFloorFeed(
        activeWorkspace!.id,
        floor: viewingFloor?.queryValue,
      );
      _handleFeedUpdate(snapshot);
    } catch (_) {}
  }

  Future<void> _subscribeFeed() async {
    if (activeWorkspace == null) return;

    try {
      await feedSocket.connect(
        workspaceId: activeWorkspace!.id,
        floorId: viewingFloor?.queryValue,
      );

      _feedSubscription?.cancel();
      _feedSubscription = feedSocket.updates.listen((data) {
        _handleFeedUpdate(data);
      });
    } catch (e) {
      // Ignora erro passageiro de websocket
    }
  }

  /// Mostra outro andar do workspace (só o cliente; o host continua no andar ativo).
  Future<void> viewFloor(FloorMeta floor) async {
    viewingFloor = floor.isActive ? null : floor;
    notifyListeners();
    await _subscribeFeed();
    await refreshFeed();
  }

  /// Novo andar no workspace ativo. Retorna o id criado.
  Future<String?> createFloor(String name, {bool gitIsolation = false}) async {
    if (activeWorkspace == null) return null;
    final id = await client.createFloor(activeWorkspace!.id, name: name, gitIsolation: gitIsolation);
    await refreshFeed();
    return id;
  }

  Future<void> renameFloor(FloorMeta floor, String name) async {
    if (activeWorkspace == null) return;
    await client.renameFloor(activeWorkspace!.id, floor, name);
    await refreshFeed();
  }

  /// Descarrega o andar: para os terminais dele (voltam ao visitar o andar).
  Future<void> unloadFloor(FloorMeta floor) async {
    if (activeWorkspace == null) return;
    await client.unloadFloor(activeWorkspace!.id, floor);
    await refreshFeed();
  }

  /// Prévia de aterrissagem (só leitura).
  Future<FloorLanding> getLandingPreview(FloorMeta floor, {String? target}) =>
      client.getLandingPreview(_wsId, floor, target: target);

  /// Aterrissa o andar. Uma recusa do host (409) é lançada com as palavras dele.
  Future<Map<String, dynamic>> landFloor(
    FloorMeta floor, {
    String? targetBranch,
    bool deleteBranch = false,
    bool keepFloor = false,
  }) async {
    final result = await client.landFloor(
      _wsId,
      floor,
      targetBranch: targetBranch,
      deleteBranch: deleteBranch,
      keepFloor: keepFloor,
    );
    if (!keepFloor && viewingFloor?.queryValue == floor.queryValue) viewingFloor = null;
    await refreshFeed();
    return result;
  }

  Future<void> deleteFloor(FloorMeta floor, {bool deleteBranch = false, bool force = false}) async {
    if (activeWorkspace == null) return;
    await client.deleteFloor(activeWorkspace!.id, floor, deleteBranch: deleteBranch, force: force);
    if (viewingFloor?.queryValue == floor.queryValue) viewingFloor = null;
    await refreshFeed();
  }

  /// Ativa um andar no host (escrita, visível no host). Recarrega o feed depois.
  Future<void> activateFloor(FloorMeta floor) async {
    if (activeWorkspace == null) return;
    await client.activateFloor(activeWorkspace!.id, floor);
    await refreshFeed();
  }

  // ---------------------------------------------------------------------------
  // Workspace id do contexto atual. Operações de andar só valem para o ativo.
  String get _wsId {
    final ws = activeWorkspace;
    if (ws == null) throw StateError('Nenhum workspace ativo');
    return ws.id;
  }

  /// Relato do andar (owner). Substitui o relato inteiro.
  Future<void> setFloorStatus(
    FloorMeta floor, {
    required String state,
    required String text,
    double? progress,
  }) async {
    await client.setFloorStatus(_wsId, floor, state: state, text: text, progress: progress);
    await refreshFeed();
  }

  /// Limpa o relato do andar.
  Future<void> clearFloorStatus(FloorMeta floor) async {
    await client.clearFloorStatus(_wsId, floor);
    await refreshFeed();
  }

  // Pull requests do andar ----------------------------------------------------
  Future<PullRequestContext> getPullRequestContext(FloorMeta floor, {String? base}) =>
      client.getPullRequestContext(_wsId, floor, base: base);

  Future<PullRequestOpened> openPullRequest(
    FloorMeta floor, {
    required String base,
    required String title,
    String body = '',
    bool? draft,
    bool? onWebsite,
  }) async {
    final opened = await client.openPullRequest(
      _wsId,
      floor,
      base: base,
      title: title,
      body: body,
      draft: draft,
      onWebsite: onWebsite,
    );
    await refreshFeed();
    return opened;
  }

  Future<void> checkPullRequest(FloorMeta floor) async {
    await client.checkPullRequest(_wsId, floor);
    await refreshFeed();
  }

  Future<void> mergePullRequest(FloorMeta floor, {required String method}) async {
    await client.mergePullRequest(_wsId, floor, method: method);
    await refreshFeed();
  }

  Future<void> pushPullRequest(FloorMeta floor) async {
    await client.pushPullRequest(_wsId, floor);
    await refreshFeed();
  }

  Future<PullRequestRemoved> removePullRequest(FloorMeta floor, {bool confirmExtraWork = false}) async {
    final removed = await client.removePullRequest(_wsId, floor, confirmExtraWork: confirmExtraWork);
    if (viewingFloor?.queryValue == floor.queryValue) viewingFloor = null;
    await refreshFeed();
    return removed;
  }

  Future<void> handOffPullRequest(
    FloorMeta floor, {
    required String terminalId,
    required String task,
    String? note,
  }) async {
    await client.handOffPullRequest(_wsId, floor, terminalId: terminalId, task: task, note: note);
    await refreshFeed();
  }

  Future<void> forgetPullRequest(FloorMeta floor) async {
    await client.forgetPullRequest(_wsId, floor);
    await refreshFeed();
  }

  // Hooks de andar (owner, capability floorHooks) ----------------------------
  Future<FloorHooksSnapshot> getFloorHooks() => client.getFloorHooks(_wsId);

  Future<void> saveFloorHooks(FloorHooks hooks) => client.putFloorHooks(_wsId, hooks);

  /// `action` é run, stop ou runSection (ver `FloorsApi`/`HooksApi`).
  Future<void> floorHookAction(
    FloorMeta floor, {
    required String action,
    String? commandId,
    String? section,
  }) async {
    await client.floorHookAction(_wsId, floor, action: action, commandId: commandId, section: section);
    await refreshFeed();
  }

  // Workspaces e barra lateral -----------------------------------------------
  /// Recarrega a lista de workspaces e o layout da barra lateral.
  Future<void> refreshWorkspaces() async {
    if (client.authToken == null) return;
    try {
      final listing = await client.listWorkspacesWithLayout();
      workspaces = listing.workspaces;
      sidebarLayout = listing.layout;
      final current = activeWorkspace;
      if (current != null) {
        for (final w in workspaces) {
          if (w.id == current.id) {
            activeWorkspace = w;
            break;
          }
        }
      }
      notifyListeners();
    } catch (_) {
      // Lista antiga continua na tela; o próximo refresh tenta de novo
    }
  }

  /// Novo workspace. Retorna o id criado. 404 = diretório ausente (tente com createDirectory).
  Future<String> createWorkspace({
    required String name,
    String? color,
    String? workingDirectory,
    bool createDirectory = false,
    WorkspacePlacement placement = WorkspacePlacement.topLevel,
  }) async {
    final id = await client.createWorkspace(
      name: name,
      color: color,
      workingDirectory: workingDirectory,
      createDirectory: createDirectory,
      placement: placement,
    );
    await refreshWorkspaces();
    return id;
  }

  Future<void> updateWorkspace(
    WorkspaceMeta ws, {
    String? name,
    String? color,
    String? workingDirectory,
    bool createDirectory = false,
    WorkspacePlacement? placement,
  }) async {
    await client.updateWorkspace(
      ws.id,
      name: name,
      color: color,
      workingDirectory: workingDirectory,
      createDirectory: createDirectory,
      placement: placement,
    );
    await refreshWorkspaces();
  }

  Future<void> renameWorkspace(WorkspaceMeta ws, String name) async {
    await client.renameWorkspace(ws.id, name);
    await refreshWorkspaces();
  }

  Future<void> pinWorkspace(WorkspaceMeta ws, {required bool pinned}) async {
    await client.pinWorkspace(ws.id, pinned: pinned);
    await refreshWorkspaces();
  }

  Future<void> wakeWorkspace(WorkspaceMeta ws) async {
    await client.wakeWorkspace(ws.id);
    await refreshWorkspaces();
  }

  Future<void> unloadWorkspace(WorkspaceMeta ws) async {
    await client.unloadWorkspace(ws.id);
    await refreshWorkspaces();
    if (activeWorkspace?.id == ws.id) await refreshFeed();
  }

  Future<void> clearWorkspaceAttention(WorkspaceMeta ws) async {
    await client.clearWorkspaceAttention(ws.id);
    await refreshWorkspaces();
  }

  /// Exclui o workspace no host (a confirmação é da UI). Se era o ativo, troca
  /// para o primeiro restante.
  Future<void> deleteWorkspace(WorkspaceMeta ws) async {
    await client.deleteWorkspace(ws.id);
    final wasActive = activeWorkspace?.id == ws.id;
    await refreshWorkspaces();
    if (wasActive) {
      activeWorkspace = null;
      floors = [];
      viewingFloor = null;
      final next = workspaces.isEmpty ? null : workspaces.first;
      if (next != null) {
        await selectWorkspace(next);
      } else {
        notifyListeners();
      }
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
      
      final floorList = feedPayload['floors'];
      if (floorList is List) {
        floors = [
          for (final f in floorList)
            if (f is Map<String, dynamic>) FloorMeta.fromJson(f),
        ];
      }

      final workspaceData = feedPayload['workspace'];
      if (workspaceData is Map && workspaceData['ropeRouting'] is String) {
        ropeRouting = workspaceData['ropeRouting'] as String;
      }

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
