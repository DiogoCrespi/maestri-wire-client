import 'dart:convert';
import '../../models/agent_preset.dart';
import 'wire_client.dart';

/// Erro devolvido pelo host nas rotas de terminal (400, 404...).
class TerminalsApiException implements Exception {
  final int statusCode;
  final String message;

  const TerminalsApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Corpo de criação de um terminal (`POST /api/workspaces/{ws}/terminals`).
///
/// Todo campo nulo fica de fora do corpo, e então vale o que o preset define.
/// Campos presentes vencem o preset. `maestroMode` vai sempre, como booleano.
class TerminalDraft {
  /// Preset de origem. Nulo quando o host não tem presets (exige `command`).
  final String? presetId;

  /// Andar de destino. Nulo é o térreo.
  final String? floorId;
  final String? name;
  final String? command;

  /// Nome de ícone do host (ex.: `seal`, `brain`).
  final String? icon;

  /// `#RRGGBB`.
  final String? color;
  final bool? monitorActivity;
  final bool maestroMode;

  /// Id de responsabilidade (`GET /api/roles`).
  final String? roleId;
  final double? x;
  final double? y;

  const TerminalDraft({
    this.presetId,
    this.floorId,
    this.name,
    this.command,
    this.icon,
    this.color,
    this.monitorActivity,
    this.maestroMode = false,
    this.roleId,
    this.x,
    this.y,
  });

  Map<String, dynamic> toJson() => {
        if (presetId != null) 'presetId': presetId,
        if (floorId != null) 'floorId': floorId,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (name != null && name!.isNotEmpty) 'name': name,
        if (command != null) 'command': command,
        if (icon != null && icon!.isNotEmpty) 'icon': icon,
        if (color != null && color!.isNotEmpty) 'color': color,
        if (monitorActivity != null) 'monitorActivity': monitorActivity,
        'maestroMode': maestroMode,
        if (roleId != null && roleId!.isNotEmpty) 'roleId': roleId,
      };
}

/// Presets de agente e criação de terminais no canvas.
extension TerminalsApi on WireClient {
  /// `GET /api/agent-presets`: só a lista de presets.
  Future<List<AgentPreset>> listPresets() async {
    final json = await getJson('/api/agent-presets');
    return AgentPreset.listFromJson(json);
  }

  /// `GET /api/agent-presets` completo: presets, temas e aparência padrão.
  /// Use `AgentPresetCatalog.supportsAppearance` para esconder os controles de
  /// aparência com um host mais antigo.
  Future<AgentPresetCatalog> getPresetCatalog() async {
    final json = await getJson('/api/agent-presets');
    return AgentPresetCatalog.fromJson(json);
  }

  /// Forma antiga (preset + nome + posição). Mantida para os chamadores atuais;
  /// novos chamadores usam [createTerminalFromDraft].
  Future<({String nodeId, String terminalId})> createTerminal({
    required String workspaceId,
    required String presetId,
    required String name,
    double x = 0,
    double y = 0,
    bool maestroMode = false,
  }) =>
      createTerminalFromDraft(
        workspaceId: workspaceId,
        draft: TerminalDraft(
          presetId: presetId,
          name: name,
          x: x,
          y: y,
          maestroMode: maestroMode,
        ),
      );

  /// `POST /api/workspaces/{ws}/terminals` com o rascunho completo. Devolve os
  /// ids do nó e do terminal. `404`: preset ou responsabilidade não encontrada.
  /// `400`: nada para rodar, ou cor que não seja `#RRGGBB`.
  Future<({String nodeId, String terminalId})> createTerminalFromDraft({
    required String workspaceId,
    required TerminalDraft draft,
  }) async {
    final res = await sendJson(
      'POST',
      '/api/workspaces/$workspaceId/terminals',
      draft.toJson(),
    );
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw TerminalsApiException(
        res.statusCode,
        'Criar terminal respondeu ${res.statusCode}: $text',
      );
    }
    final decoded = jsonDecode(text);
    final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final nodeId = (json['nodeId'] ?? '').toString();
    final terminalId = (json['terminalId'] ?? '').toString();
    if (nodeId.isEmpty || terminalId.isEmpty) {
      throw TerminalsApiException(res.statusCode, 'Resposta sem nodeId/terminalId: $text');
    }
    return (nodeId: nodeId, terminalId: terminalId);
  }
}
