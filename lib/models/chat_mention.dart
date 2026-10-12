/// Item de um seletor de `@` (`GET …/mentions`). Ações (`createNote`, …) também
/// chegam aqui; um cliente só mostra as que o catálogo listou.
class ChatMention {
  final String kind;
  final String id;
  final String name;
  final String? tokenName;
  final String floorName;
  final String section;
  final bool isOnActiveFloor;

  const ChatMention({
    required this.kind,
    required this.id,
    required this.name,
    this.tokenName,
    this.floorName = '',
    this.section = '',
    this.isOnActiveFloor = true,
  });

  /// Texto inserido no compositor, sem o espaço final.
  String get insertText => '@${(tokenName ?? name).trim()}';

  factory ChatMention.fromJson(Map<String, dynamic> json) {
    return ChatMention(
      kind: (json['kind'] ?? '').toString(),
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      tokenName: json['tokenName'] as String?,
      floorName: (json['floorName'] ?? '').toString(),
      section: (json['section'] ?? '').toString(),
      isOnActiveFloor: json['isOnActiveFloor'] != false,
    );
  }

  static List<ChatMention> listFromJson(Map<String, dynamic> json) {
    final raw = json['mentions'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map<String, dynamic>) ChatMention.fromJson(e),
    ];
  }
}

/// Entrada do índice de arquivos do host (`GET …/files`), relativa ao diretório do terminal.
class ChatFileEntry {
  final String relativePath;
  final String name;
  final bool isDirectory;

  const ChatFileEntry({required this.relativePath, required this.name, required this.isDirectory});

  factory ChatFileEntry.fromJson(Map<String, dynamic> json) {
    final rel = (json['relativePath'] ?? json['name'] ?? '').toString();
    return ChatFileEntry(
      relativePath: rel,
      name: (json['name'] ?? rel.split('/').last).toString(),
      isDirectory: json['isDirectory'] == true,
    );
  }
}

class ChatFileListing {
  final String query;
  final String root;
  final List<ChatFileEntry> entries;
  final bool isTruncated;

  const ChatFileListing({
    required this.query,
    required this.root,
    required this.entries,
    this.isTruncated = false,
  });

  factory ChatFileListing.fromJson(Map<String, dynamic> json) {
    final raw = json['entries'];
    return ChatFileListing(
      query: (json['query'] ?? '').toString(),
      root: (json['root'] ?? '').toString(),
      entries: raw is List
          ? [
              for (final e in raw)
                if (e is Map<String, dynamic>) ChatFileEntry.fromJson(e),
            ]
          : const [],
      isTruncated: json['isTruncated'] == true,
    );
  }
}
