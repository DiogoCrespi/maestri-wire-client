/// Conteúdo de uma nota do canvas: GET /api/workspaces/{ws}/nodes/{id}/note
///
/// `revision` são os 16 primeiros hexadecimais do SHA-256 do texto. Gravar com
/// `ifRevision` impede sobrescrever uma edição feita no host no meio do caminho.
class NoteContent {
  final String nodeId;
  final String displayName;
  final String text;
  final String revision;
  final bool isLocked;
  final String? color;

  const NoteContent({
    required this.nodeId,
    required this.displayName,
    required this.text,
    required this.revision,
    required this.isLocked,
    this.color,
  });

  factory NoteContent.fromJson(Map<String, dynamic> json) {
    return NoteContent(
      nodeId: (json['nodeId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      revision: (json['revision'] ?? '').toString(),
      isLocked: json['isContentLocked'] == true,
      color: json['color'] as String?,
    );
  }
}

/// Resultado de gravar uma nota: ok, ou conflito (412) com a versão atual do host.
class NoteSaveResult {
  final bool saved;
  final bool conflict;
  final bool locked;
  final NoteContent? current;

  const NoteSaveResult({
    required this.saved,
    this.conflict = false,
    this.locked = false,
    this.current,
  });
}

extension NoteContentCopy on NoteContent {
  /// Cópia com a trava de conteúdo atualizada (usado quando o host muda só a trava).
  NoteContent withLocked(bool locked) => NoteContent(
        nodeId: nodeId,
        displayName: displayName,
        text: text,
        revision: revision,
        isLocked: locked,
        color: color,
      );
}
