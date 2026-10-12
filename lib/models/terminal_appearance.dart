// Aparência de um terminal (`appearance` nas configurações, nos presets e nos
// corpos de criação). Contrato: notes/maestri-wire.md, seção "Terminais".
//
// Os campos de tipografia (terminalFontSize, chatFont, chatTextSize) são do
// próprio cliente: nunca mudam as fontes do host.

/// Um tema que o host conhece (`themes` das configurações e dos presets).
class ThemeOption {
  final String id;
  final String name;
  final bool isLight;

  const ThemeOption({required this.id, required this.name, this.isLight = false});

  factory ThemeOption.fromJson(Map<String, dynamic> json) => ThemeOption(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? json['id'] ?? '').toString(),
        isLight: json['isLight'] == true,
      );

  /// Lê uma lista `[{id, name, isLight}]`, ignorando entradas inválidas.
  static List<ThemeOption> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => ThemeOption.fromJson(Map<String, dynamic>.from(m)))
        .where((t) => t.id.isNotEmpty)
        .toList();
  }
}

/// Valores de `theme`.
const kAppearanceThemes = ['system', 'dark', 'light', 'custom'];

/// Valores de `chatFont`.
const kChatFonts = ['system', 'monospaced', 'rounded', 'serif'];

/// Valores de `chatTextSize`.
const kChatTextSizes = [
  'system',
  'small',
  'medium',
  'large',
  'extraLarge',
  'extraExtraLarge',
];

/// Limites de `terminalFontSize` (sobreposição do cliente).
const kTerminalFontSizeMin = 8;
const kTerminalFontSizeMax = 24;

class TerminalAppearance {
  /// `system`, `dark`, `light` ou `custom`.
  final String theme;

  /// Id de um tema do host; só faz sentido com `theme == custom`.
  final String? customThemeId;

  /// Tema escuro pareado a um claro. Preservado; a tela não o edita.
  final String? darkThemeId;

  /// 8…24, ou null para o dimensionamento automático.
  final int? terminalFontSize;

  /// `system`, `monospaced`, `rounded` ou `serif`.
  final String chatFont;

  /// `system`, `small`, `medium`, `large`, `extraLarge` ou `extraExtraLarge`.
  final String chatTextSize;

  final bool startInChatMode;

  const TerminalAppearance({
    this.theme = 'system',
    this.customThemeId,
    this.darkThemeId,
    this.terminalFontSize,
    this.chatFont = 'system',
    this.chatTextSize = 'system',
    this.startInChatMode = false,
  });

  factory TerminalAppearance.fromJson(Map<String, dynamic> json) {
    String str(Object? v, String fallback) =>
        v is String && v.isNotEmpty ? v : fallback;
    String? optStr(Object? v) => v is String && v.isNotEmpty ? v : null;
    final size = json['terminalFontSize'];
    return TerminalAppearance(
      theme: str(json['theme'], 'system'),
      customThemeId: optStr(json['customThemeId']),
      darkThemeId: optStr(json['darkThemeId']),
      terminalFontSize: size is num ? size.round() : null,
      chatFont: str(json['chatFont'], 'system'),
      chatTextSize: str(json['chatTextSize'], 'system'),
      startInChatMode: json['startInChatMode'] == true,
    );
  }

  /// Corpo `appearance`. Com [base] (o veio do host), as chaves desconhecidas
  /// dele são preservadas; as conhecidas são substituídas. Campos nulos saem.
  Map<String, dynamic> toJson({Map<String, dynamic>? base}) {
    final out = <String, dynamic>{...?base};
    out['theme'] = theme;
    out['chatFont'] = chatFont;
    out['chatTextSize'] = chatTextSize;
    out['startInChatMode'] = startInChatMode;
    _setOrRemove(out, 'customThemeId', theme == 'custom' ? customThemeId : null);
    _setOrRemove(out, 'darkThemeId', darkThemeId);
    _setOrRemove(out, 'terminalFontSize', terminalFontSize);
    return out;
  }

  static void _setOrRemove(Map<String, dynamic> m, String key, Object? value) {
    if (value == null) {
      m.remove(key);
    } else {
      m[key] = value;
    }
  }

  TerminalAppearance copyWith({
    String? theme,
    String? customThemeId,
    bool clearCustomThemeId = false,
    String? darkThemeId,
    int? terminalFontSize,
    bool clearTerminalFontSize = false,
    String? chatFont,
    String? chatTextSize,
    bool? startInChatMode,
  }) {
    return TerminalAppearance(
      theme: theme ?? this.theme,
      customThemeId: clearCustomThemeId ? null : (customThemeId ?? this.customThemeId),
      darkThemeId: darkThemeId ?? this.darkThemeId,
      terminalFontSize:
          clearTerminalFontSize ? null : (terminalFontSize ?? this.terminalFontSize),
      chatFont: chatFont ?? this.chatFont,
      chatTextSize: chatTextSize ?? this.chatTextSize,
      startInChatMode: startInChatMode ?? this.startInChatMode,
    );
  }
}

/// `#RRGGBB` com seis dígitos hexadecimais, como o host exige para `color`.
bool isHexColor(String s) => RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(s);

/// Converte `#RRGGBB` para um inteiro ARGB opaco (para `Color(...)`).
/// Devolve null para um valor inválido.
int? hexColorToArgb(String s) {
  if (!isHexColor(s)) return null;
  return 0xFF000000 | int.parse(s.substring(1), radix: 16);
}
