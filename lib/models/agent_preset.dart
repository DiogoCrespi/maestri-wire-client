import 'terminal_appearance.dart';

/// Preset de agente (`GET /api/agent-presets`). Pertence ao host.
///
/// `command` é vazio ou ausente para presets sem comando (Shell).
/// `appearance` é a aparência resolvida do preset; ausente num host antigo.
class AgentPreset {
  final String id;
  final String name;
  final String agentType;
  final String icon;
  final bool isManager;
  final bool isDefault;
  final String? command;
  final String? color;
  final TerminalAppearance? appearance;

  const AgentPreset({
    required this.id,
    required this.name,
    required this.agentType,
    required this.icon,
    this.isManager = false,
    this.isDefault = false,
    this.command,
    this.color,
    this.appearance,
  });

  /// `startInChatMode` do preset; falso quando ausente.
  bool get startInChatMode => appearance?.startInChatMode ?? false;

  factory AgentPreset.fromJson(Map<String, dynamic> json) {
    final cmd = json['command'];
    final col = json['color'];
    final app = json['appearance'];
    return AgentPreset(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      agentType: (json['agentType'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
      isManager: json['isManager'] == true,
      isDefault: json['isDefault'] == true,
      command: cmd is String && cmd.trim().isNotEmpty ? cmd : null,
      color: col is String && col.isNotEmpty ? col : null,
      appearance: app is Map
          ? TerminalAppearance.fromJson(Map<String, dynamic>.from(app))
          : null,
    );
  }

  /// Lê o corpo completo de `GET /api/agent-presets` (`{presets: [...]}`).
  static List<AgentPreset> listFromJson(Map<String, dynamic> json) {
    final raw = json['presets'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AgentPreset.fromJson)
        .where((p) => p.id.isNotEmpty)
        .toList();
  }
}

/// Catálogo completo de `GET /api/agent-presets`: presets mais os temas que o
/// host conhece e a aparência padrão. `defaultAppearance` ausente (host antigo)
/// significa que os controles de aparência devem ficar escondidos.
class AgentPresetCatalog {
  final List<AgentPreset> presets;
  final List<ThemeOption> themes;
  final TerminalAppearance? defaultAppearance;

  const AgentPresetCatalog({
    required this.presets,
    this.themes = const [],
    this.defaultAppearance,
  });

  bool get supportsAppearance => defaultAppearance != null;

  factory AgentPresetCatalog.fromJson(Map<String, dynamic> json) {
    final app = json['defaultAppearance'];
    return AgentPresetCatalog(
      presets: AgentPreset.listFromJson(json),
      themes: ThemeOption.listFromJson(json['themes']),
      defaultAppearance: app is Map
          ? TerminalAppearance.fromJson(Map<String, dynamic>.from(app))
          : null,
    );
  }
}
