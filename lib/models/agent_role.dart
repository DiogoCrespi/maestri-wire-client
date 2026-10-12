/// Responsabilidade de agente (capability `roleManagement`).
///
/// As responsabilidades pertencem ao host. `workspaceId` ausente significa global.
class AgentRole {
  final String id;
  final String name;
  final String prompt;
  final String icon;
  final String color;
  final String? workspaceId;
  final int terminalsInUse;

  const AgentRole({
    required this.id,
    required this.name,
    required this.prompt,
    required this.icon,
    required this.color,
    this.workspaceId,
    this.terminalsInUse = 0,
  });

  factory AgentRole.fromJson(Map<String, dynamic> json) {
    final ws = json['workspaceId'];
    return AgentRole(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      prompt: (json['prompt'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
      color: (json['color'] ?? '').toString(),
      workspaceId: ws is String && ws.isNotEmpty ? ws : null,
      terminalsInUse: json['terminalsInUse'] is int ? json['terminalsInUse'] as int : 0,
    );
  }

  /// Corpo de `RoleWrite` para criar ou substituir a responsabilidade.
  RoleWrite toWrite() => RoleWrite(
        name: name,
        prompt: prompt,
        icon: icon,
        color: color,
        workspaceId: workspaceId,
      );
}

/// `RoleWrite`: corpo de POST e PUT de responsabilidades.
/// PUT é substituição completa, então `workspaceId` existente deve ser reenviado.
class RoleWrite {
  final String name;
  final String prompt;
  final String icon;
  final String color;
  final String? workspaceId;

  const RoleWrite({
    required this.name,
    required this.prompt,
    required this.icon,
    required this.color,
    this.workspaceId,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'prompt': prompt,
        'icon': icon,
        'color': color,
        if (workspaceId != null) 'workspaceId': workspaceId,
      };
}

/// Configurações de um terminal (`GET /api/terminals/{id}/settings`).
class TerminalSettings {
  final String command;
  final String workingDirectory;
  final String? roleId;
  final List<AgentRoleRef> roles;
  final bool maestroMode;
  final String? icon;
  final String? color;
  final bool? monitorActivity;
  final Map<String, dynamic>? appearance;

  const TerminalSettings({
    required this.command,
    required this.workingDirectory,
    required this.roleId,
    required this.roles,
    required this.maestroMode,
    this.icon,
    this.color,
    this.monitorActivity,
    this.appearance,
  });

  factory TerminalSettings.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    final rawAppearance = json['appearance'];
    return TerminalSettings(
      command: (json['command'] ?? '').toString(),
      workingDirectory: (json['workingDirectory'] ?? '').toString(),
      roleId: json['roleId'] is String && (json['roleId'] as String).isNotEmpty
          ? json['roleId'] as String
          : null,
      roles: rawRoles is List
          ? rawRoles
              .whereType<Map<String, dynamic>>()
              .map(AgentRoleRef.fromJson)
              .toList()
          : const [],
      maestroMode: json['maestroMode'] == true,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      monitorActivity: json['monitorActivity'] is bool ? json['monitorActivity'] as bool : null,
      appearance: rawAppearance is Map<String, dynamic> ? rawAppearance : null,
    );
  }

  /// Corpo do `PUT /api/terminals/{id}/settings` (substituição completa).
  /// Mantém todos os campos atuais e troca só a responsabilidade. `roleId`
  /// null remove a responsabilidade (a chave é omitida).
  Map<String, dynamic> toPutBody({required String? roleId}) => {
        'command': command,
        if (roleId != null) 'roleId': roleId,
        'maestroMode': maestroMode,
        if (icon != null) 'icon': icon,
        if (color != null) 'color': color,
        if (monitorActivity != null) 'monitorActivity': monitorActivity,
        if (appearance != null) 'appearance': appearance,
      };
}

/// Referência leve de responsabilidade dentro das configurações do terminal.
class AgentRoleRef {
  final String id;
  final String name;
  final String icon;
  final String color;

  const AgentRoleRef({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });

  factory AgentRoleRef.fromJson(Map<String, dynamic> json) => AgentRoleRef(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        icon: (json['icon'] ?? '').toString(),
        color: (json['color'] ?? '').toString(),
      );
}
