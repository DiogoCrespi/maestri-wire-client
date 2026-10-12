import 'dart:ui' show Offset, Size;

/// Leitores tolerantes para o JSON do host. Nunca lançam: valor ausente ou de
/// tipo errado vira `null` (ou o fallback informado).

String? readString(Object? raw) => raw is String ? raw : null;

String readStringOr(Object? raw, String fallback) => raw is String ? raw : fallback;

double? readDouble(Object? raw) => raw is num ? raw.toDouble() : null;

double readDoubleOr(Object? raw, double fallback) =>
    raw is num ? raw.toDouble() : fallback;

int? readInt(Object? raw) => raw is num ? raw.toInt() : null;

int readIntOr(Object? raw, int fallback) => raw is num ? raw.toInt() : fallback;

bool readBoolOr(Object? raw, bool fallback) => raw is bool ? raw : fallback;

/// Aceita `{x, y}` ou `[x, y]`.
Offset? readOffset(Object? raw) {
  if (raw is Map) {
    final x = raw['x'];
    final y = raw['y'];
    if (x is num && y is num) return Offset(x.toDouble(), y.toDouble());
    return null;
  }
  if (raw is List && raw.length >= 2) {
    final x = raw[0];
    final y = raw[1];
    if (x is num && y is num) return Offset(x.toDouble(), y.toDouble());
  }
  return null;
}

/// Aceita `{width, height}` ou `[w, h]`.
Size? readSize(Object? raw) {
  if (raw is Map) {
    final w = raw['width'];
    final h = raw['height'];
    if (w is num && h is num) return Size(w.toDouble(), h.toDouble());
    return null;
  }
  if (raw is List && raw.length >= 2) {
    final w = raw[0];
    final h = raw[1];
    if (w is num && h is num) return Size(w.toDouble(), h.toDouble());
  }
  return null;
}

/// Lista de pontos; entradas inválidas são descartadas.
List<Offset> readOffsets(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final p in raw)
      if (readOffset(p) case final o?) o,
  ];
}

/// Lista de strings; entradas que não são string são descartadas.
List<String> readStrings(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final s in raw)
      if (s is String) s,
  ];
}

/// Converte um objeto JSON (com chaves String) para `Map<String, dynamic>`;
/// qualquer outra coisa vira `null`.
Map<String, dynamic>? readMap(Object? raw) {
  if (raw is! Map) return null;
  return {for (final e in raw.entries) e.key.toString(): e.value};
}
