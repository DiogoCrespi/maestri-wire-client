/// Tipo de corda (`Connection.kind` do contrato). Valor desconhecido vira
/// [desconhecido], para que um host mais novo não quebre o cliente.
enum ConnectionKind {
  terminal('terminal'),
  note('note'),
  noteToNote('noteToNote'),
  portal('portal'),
  portalToPortal('portalToPortal'),
  crossFloor('crossFloor'),
  crossWorkspace('crossWorkspace'),
  desconhecido('desconhecido');

  const ConnectionKind(this.wire);

  /// String exata que o host envia.
  final String wire;

  static ConnectionKind parse(Object? raw) {
    if (raw is String) {
      for (final k in values) {
        if (k.wire == raw) return k;
      }
    }
    return ConnectionKind.desconhecido;
  }
}
