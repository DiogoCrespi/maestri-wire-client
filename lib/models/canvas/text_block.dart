import 'json_values.dart';

/// Payload `text` de um `CanvasNode`: bloco de texto guardado pelo host.
class TextBlock {
  final String text;
  final double fontSize;
  final bool isMonospaced;

  /// Cor em hex, quando o host envia.
  final String? color;

  /// `"serif"` ou ausente.
  final String? fontFamily;

  /// `"medium"`, `"bold"` ou ausente.
  final String? fontWeight;

  /// Fonte que o host tem.
  final String? fontName;

  const TextBlock({
    this.text = '',
    this.fontSize = 14,
    this.isMonospaced = false,
    this.color,
    this.fontFamily,
    this.fontWeight,
    this.fontName,
  });

  factory TextBlock.fromJson(Map<String, dynamic> json) {
    return TextBlock(
      text: readStringOr(json['text'], ''),
      fontSize: readDoubleOr(json['fontSize'], 14),
      isMonospaced: readBoolOr(json['isMonospaced'], false),
      color: readString(json['color']),
      fontFamily: readString(json['fontFamily']),
      fontWeight: readString(json['fontWeight']),
      fontName: readString(json['fontName']),
    );
  }

  /// Entradas que não são objeto são descartadas.
  static List<TextBlock> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (readMap(e) case final m?) TextBlock.fromJson(m),
    ];
  }
}
