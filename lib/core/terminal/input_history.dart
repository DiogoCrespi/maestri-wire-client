/// Histórico de mensagens enviadas no campo do terminal, navegado com ↑ e ↓.
///
/// ↑ volta para mensagens anteriores (a mais recente primeiro). ↓ avança e, ao
/// passar da mais recente, devolve o rascunho que estava sendo digitado.
class InputHistory {
  final List<String> _sent = [];
  int _index = -1;
  String _draft = '';

  bool get isBrowsing => _index != -1;

  void add(String message) {
    if (message.trim().isEmpty) return;
    _sent.add(message);
    _index = -1;
    _draft = '';
  }

  /// Próxima mensagem ao subir. [current] é o que está no campo agora (vira rascunho na primeira subida).
  /// Retorna null quando não há nada para mostrar.
  String? previous(String current) {
    if (_sent.isEmpty) return null;
    if (_index == -1) {
      _draft = current;
      _index = _sent.length - 1;
    } else if (_index > 0) {
      _index--;
    }
    return _sent[_index];
  }

  /// Próxima mensagem ao descer. Ao passar da última, volta ao rascunho.
  String? next() {
    if (_index == -1) return null;
    if (_index < _sent.length - 1) {
      _index++;
      return _sent[_index];
    }
    _index = -1;
    return _draft;
  }
}
