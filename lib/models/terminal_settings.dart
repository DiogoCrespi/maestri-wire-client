// Configurações de um terminal (GET/PUT /api/terminals/{id}/settings).
// Contrato: notes/maestri-wire.md, seção "Terminais".
//
// O PUT é substituição COMPLETA: o corpo deve levar tudo que o GET trouxe
// (command, icon, color, monitorActivity, roleId, appearance), senão o host
// zera o que faltar. Use [toPutBody] para montar o corpo a partir do GET.

import 'terminal_appearance.dart';

String? _nonEmpty(Object? v) {
  if (v is! String) return null;
  return v.isEmpty ? null : v;
}

/// Responsabilidade como o GET das configurações a lista (`roles`).
class TerminalRoleRef {
  final String id;
  final String name;
  final String icon;
  final String color;

  const TerminalRoleRef({
    required this.id,
    required this.name,
    this.icon = '',
    this.color = '',
  });

  factory TerminalRoleRef.fromJson(Map<String, dynamic> json) => TerminalRoleRef(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        icon: (json['icon'] ?? '').toString(),
        color: (json['color'] ?? '').toString(),
      );
}

class TerminalSettings {
  final String command;
  final String workingDirectory;
  final String? roleId;
  final bool maestroMode;
  final String? icon;
  final String? color;
  final bool monitorActivity;

  /// Responsabilidades que o host tem (`roles`); vazio em host antigo.
  final List<TerminalRoleRef> roles;

  /// Temas que `customThemeId` pode nomear (`themes`); vazio em host antigo.
  final List<ThemeOption> themes;

  /// Aparência como veio do host. Preservada para o PUT (chaves desconhecidas
  /// inclusive). Use [appearanceModel] para ler os campos conhecidos.
  final Map<String, dynamic>? appearance;

  const TerminalSettings({
    required this.command,
    this.workingDirectory = '',
    this.roleId,
    this.maestroMode = false,
    this.icon,
    this.color,
    this.monitorActivity = false,
    this.roles = const [],
    this.themes = const [],
    this.appearance,
  });

  /// Aparência tipada, ou null quando o host não a informa (host antigo).
  TerminalAppearance? get appearanceModel => appearance == null
      ? null
      : TerminalAppearance.fromJson(appearance!);

  factory TerminalSettings.fromJson(Map<String, dynamic> json) {
    final app = json['appearance'];
    final rawRoles = json['roles'];
    return TerminalSettings(
      command: json['command'] is String ? json['command'] as String : '',
      workingDirectory:
          json['workingDirectory'] is String ? json['workingDirectory'] as String : '',
      roleId: _nonEmpty(json['roleId']),
      maestroMode: json['maestroMode'] == true,
      icon: _nonEmpty(json['icon']),
      color: _nonEmpty(json['color']),
      monitorActivity: json['monitorActivity'] == true,
      roles: rawRoles is List
          ? rawRoles
              .whereType<Map>()
              .map((m) => TerminalRoleRef.fromJson(Map<String, dynamic>.from(m)))
              .where((r) => r.id.isNotEmpty)
              .toList()
          : const [],
      themes: ThemeOption.listFromJson(json['themes']),
      appearance: app is Map ? Map<String, dynamic>.from(app) : null,
    );
  }

  /// Corpo de substituição completa do PUT.
  ///
  /// Cada parâmetro nulo mantém o valor atual (o GET). Para apagar um campo
  /// use as flags `clear*`. `command` e `appearance` substituem o atual quando
  /// informados.
  Map<String, dynamic> toPutBody({
    String? command,
    bool? maestroMode,
    bool? monitorActivity,
    String? icon,
    String? color,
    String? roleId,
    TerminalAppearance? appearance,
    bool clearRole = false,
    bool clearIcon = false,
    bool clearColor = false,
  }) {
    final body = <String, dynamic>{
      'command': command ?? this.command,
      'maestroMode': maestroMode ?? this.maestroMode,
      'monitorActivity': monitorActivity ?? this.monitorActivity,
    };
    final i = clearIcon ? null : (icon ?? this.icon);
    if (i != null) body['icon'] = i;
    final c = clearColor ? null : (color ?? this.color);
    if (c != null) body['color'] = c;
    final r = clearRole ? null : (roleId ?? this.roleId);
    if (r != null) body['roleId'] = r;
    if (appearance != null) {
      body['appearance'] = appearance.toJson(base: this.appearance);
    } else if (this.appearance != null) {
      body['appearance'] = this.appearance;
    }
    return body;
  }
}
