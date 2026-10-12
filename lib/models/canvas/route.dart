import 'dart:ui' show Offset, Rect;

/// Ponta de uma corda no retângulo [from], na direção do centro de [to].
///
/// Usado quando `ropeRouting` é `circuit`, em que `Connection.points` pode estar
/// desatualizado: a corda vai de `routeEndpoints(a, b)` até `routeEndpoints(b, a)`.
/// Retorna o ponto onde a reta centro-a-centro cruza a borda de [from]; se os
/// centros coincidem, retorna o centro de [from].
Offset routeEndpoints(Rect from, Rect to) {
  final c = from.center;
  final d = to.center - c;
  if (d.dx == 0 && d.dy == 0) return c;
  final hw = from.width / 2;
  final hh = from.height / 2;
  // Fator t tal que c + d*t cai na borda de `from`.
  final tx = d.dx == 0 ? double.infinity : (hw / d.dx.abs());
  final ty = d.dy == 0 ? double.infinity : (hh / d.dy.abs());
  final t = tx < ty ? tx : ty;
  return c + d * t;
}
