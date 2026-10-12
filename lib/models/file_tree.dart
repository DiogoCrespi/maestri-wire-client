import 'dart:convert';

/// Modelos das árvores de arquivos (capability `fileTrees`).
///
/// Os caminhos são opacos: relativos à raiz, separados por `/`, `""` para a
/// raiz. O cliente mostra `name` e devolve `path` exatamente como o host
/// entregou, sem juntar, dividir ou normalizar.

String? _str(Object? v) => v is String ? v : null;
bool _bool(Object? v) => v is bool ? v : false;
int _int(Object? v) => v is num ? v.toInt() : 0;

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

List<String> _strList(Object? v) =>
    v is List ? v.whereType<String>().toList() : const <String>[];

List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : const <Map<String, dynamic>>[];

/// Payload `fileTree` de um nó do canvas.
class FileTreeNode {
  final String rootPath;
  final String currentPath;
  /// Ausente para o próprio disco do host; senão `ssh`, `docker`, `sandbox` ou `customRuntime`.
  final String? environment;
  final bool showsHiddenFiles;
  final List<String> pinnedPaths;
  final List<FileTreePreviewEntry>? preview;
  final String? branch;

  const FileTreeNode({
    required this.rootPath,
    required this.currentPath,
    this.environment,
    this.showsHiddenFiles = false,
    this.pinnedPaths = const [],
    this.preview,
    this.branch,
  });

  factory FileTreeNode.fromJson(Map<String, dynamic> json) {
    final rawPreview = json['preview'];
    return FileTreeNode(
      rootPath: _str(json['rootPath']) ?? '',
      currentPath: _str(json['currentPath']) ?? '',
      environment: _str(json['environment']),
      showsHiddenFiles: _bool(json['showsHiddenFiles']),
      pinnedPaths: _strList(json['pinnedPaths']),
      preview: rawPreview is List
          ? _maps(rawPreview).map(FileTreePreviewEntry.fromJson).toList()
          : null,
      branch: _str(json['branch']),
    );
  }
}

/// Linha da miniatura (`preview`) de um nó de árvore.
class FileTreePreviewEntry {
  final String name;
  final bool isDirectory;
  final String? gitStatus;

  const FileTreePreviewEntry({
    required this.name,
    required this.isDirectory,
    this.gitStatus,
  });

  factory FileTreePreviewEntry.fromJson(Map<String, dynamic> json) => FileTreePreviewEntry(
        name: _str(json['name']) ?? '',
        isDirectory: _bool(json['isDirectory']),
        gitStatus: _str(json['gitStatus']),
      );
}

/// Uma entrada de pasta ou resultado de busca.
class FileTreeEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final bool isSymbolicLink;
  final int size;
  final DateTime? modifiedAt;
  /// Letra do porcelain do git (`M A D R C ? ! U`); para pasta, a pior entre os filhos.
  final String? gitStatus;

  const FileTreeEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isSymbolicLink = false,
    this.size = 0,
    this.modifiedAt,
    this.gitStatus,
  });

  factory FileTreeEntry.fromJson(Map<String, dynamic> json) => FileTreeEntry(
        name: _str(json['name']) ?? '',
        path: _str(json['path']) ?? '',
        isDirectory: _bool(json['isDirectory']),
        isSymbolicLink: _bool(json['isSymbolicLink']),
        size: _int(json['size']),
        modifiedAt: _date(json['modifiedAt']),
        gitStatus: _str(json['gitStatus']),
      );
}

/// Estado git da pasta listada.
class FileTreeGitInfo {
  final String? branch;
  final int changedCount;
  final bool hasUpstream;

  const FileTreeGitInfo({this.branch, this.changedCount = 0, this.hasUpstream = false});

  factory FileTreeGitInfo.fromJson(Map<String, dynamic> json) => FileTreeGitInfo(
        branch: _str(json['branch']),
        changedCount: _int(json['changedCount']),
        hasUpstream: _bool(json['hasUpstream']),
      );
}

/// `GET …/tree?path=` : o conteúdo de uma pasta.
class FileTreeListing {
  final String path;
  final String name;
  final List<FileTreeEntry> entries;
  final bool isTruncated;
  final FileTreeGitInfo? git;

  const FileTreeListing({
    required this.path,
    required this.name,
    required this.entries,
    this.isTruncated = false,
    this.git,
  });

  factory FileTreeListing.fromJson(Map<String, dynamic> json) {
    final rawGit = json['git'];
    return FileTreeListing(
      path: _str(json['path']) ?? '',
      name: _str(json['name']) ?? '',
      entries: _maps(json['entries']).map(FileTreeEntry.fromJson).toList(),
      isTruncated: _bool(json['isTruncated']),
      git: rawGit is Map ? FileTreeGitInfo.fromJson(Map<String, dynamic>.from(rawGit)) : null,
    );
  }
}

/// `GET …/tree/search?query=`.
class FileTreeSearch {
  final String query;
  final List<FileTreeEntry> hits;
  final bool isTruncated;

  const FileTreeSearch({required this.query, required this.hits, this.isTruncated = false});

  factory FileTreeSearch.fromJson(Map<String, dynamic> json) => FileTreeSearch(
        query: _str(json['query']) ?? '',
        hits: _maps(json['hits']).map(FileTreeEntry.fromJson).toList(),
        isTruncated: _bool(json['isTruncated']),
      );
}

/// Uma mudança do repositório.
class FileTreeChange {
  final String path;
  final String name;
  final String directory;
  final String status;
  final bool isStaged;
  final int? additions;
  final int? deletions;

  const FileTreeChange({
    required this.path,
    required this.name,
    required this.directory,
    required this.status,
    required this.isStaged,
    this.additions,
    this.deletions,
  });

  factory FileTreeChange.fromJson(Map<String, dynamic> json) => FileTreeChange(
        path: _str(json['path']) ?? '',
        name: _str(json['name']) ?? '',
        directory: _str(json['directory']) ?? '',
        status: _str(json['status']) ?? '',
        isStaged: _bool(json['isStaged']),
        additions: json['additions'] is num ? (json['additions'] as num).toInt() : null,
        deletions: json['deletions'] is num ? (json['deletions'] as num).toInt() : null,
      );
}

/// `GET …/tree/changes`.
class FileTreeChanges {
  final String? branch;
  final List<FileTreeChange> staged;
  final List<FileTreeChange> unstaged;

  const FileTreeChanges({this.branch, this.staged = const [], this.unstaged = const []});

  factory FileTreeChanges.fromJson(Map<String, dynamic> json) => FileTreeChanges(
        branch: _str(json['branch']),
        staged: _maps(json['staged']).map(FileTreeChange.fromJson).toList(),
        unstaged: _maps(json['unstaged']).map(FileTreeChange.fromJson).toList(),
      );
}

/// Escopos aceitos por `GET …/tree/diff?scope=`.
enum FileTreeDiffScope {
  combined('combined'),
  staged('staged'),
  unstaged('unstaged');

  final String wire;
  const FileTreeDiffScope(this.wire);
}

/// `GET …/tree/diff?path=&scope=`.
class FileTreeDiff {
  final String path;
  final String scope;
  final String patch;

  const FileTreeDiff({required this.path, required this.scope, required this.patch});

  factory FileTreeDiff.fromJson(Map<String, dynamic> json) => FileTreeDiff(
        path: _str(json['path']) ?? '',
        scope: _str(json['scope']) ?? '',
        patch: _str(json['patch']) ?? '',
      );
}

/// Bytes de `GET …/tree/file` com `Range` (ou o arquivo inteiro).
class FileTreeBytes {
  final List<int> bytes;
  /// 200 ou 206.
  final int statusCode;
  final String? contentType;
  /// Tamanho total do arquivo, quando o host informa em `Content-Range`.
  final int? totalLength;
  /// Posição do primeiro byte deste trecho (0 quando veio inteiro).
  final int start;

  const FileTreeBytes({
    required this.bytes,
    required this.statusCode,
    this.contentType,
    this.totalLength,
    this.start = 0,
  });

  /// Verdadeiro quando há mais bytes depois deste trecho.
  bool get hasMore => totalLength != null && start + bytes.length < totalLength!;
}

/// Lê o total de `Content-Range: bytes a-b/total`. Devolve null se ausente ou `*`.
int? parseContentRangeTotal(String? header) {
  if (header == null) return null;
  final slash = header.lastIndexOf('/');
  if (slash < 0) return null;
  return int.tryParse(header.substring(slash + 1).trim());
}

/// Erro devolvido pelo host: `{"error": {"code", "message"}}`.
class FileTreeException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const FileTreeException({required this.statusCode, required this.code, required this.message});

  /// Monta a exceção a partir do status e do corpo bruto da resposta.
  factory FileTreeException.fromResponse(int statusCode, String body) {
    String code = 'unknown';
    String message = body.isEmpty ? 'HTTP $statusCode' : body;
    try {
      final decoded = _decodeMap(body);
      final err = decoded?['error'];
      if (err is Map) {
        code = _str(err['code']) ?? code;
        message = _str(err['message']) ?? message;
      }
    } catch (_) {
      // corpo não é JSON: mantém o texto bruto
    }
    return FileTreeException(statusCode: statusCode, code: code, message: message);
  }

  @override
  String toString() => 'FileTreeException($statusCode, $code): $message';
}

Map<String, dynamic>? _decodeMap(String body) {
  if (!body.trimLeft().startsWith('{')) return null;
  final decoded = jsonDecode(body);
  return decoded is Map<String, dynamic> ? decoded : null;
}

/// Pilha de navegação de uma árvore. Não junta nem divide caminhos: cada
/// crumb guarda o `path` exatamente como o host entregou.
class FileTreeCrumbs {
  final List<FileTreeCrumb> _items;

  FileTreeCrumbs(String rootName) : _items = [FileTreeCrumb(path: '', name: rootName)];

  List<FileTreeCrumb> get items => List.unmodifiable(_items);
  FileTreeCrumb get current => _items.last;
  bool get canGoUp => _items.length > 1;

  /// Entra numa pasta filha.
  void push(FileTreeEntry folder) => _items.add(FileTreeCrumb(path: folder.path, name: folder.name));

  /// Sobe um nível. Devolve falso se já estiver na raiz.
  bool up() {
    if (!canGoUp) return false;
    _items.removeLast();
    return true;
  }

  /// Vai direto a um nível da pilha.
  void jumpTo(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeRange(index + 1, _items.length);
  }

  /// Substitui a pilha por raiz + uma pasta (usado ao abrir um resultado de busca).
  void resetTo(String rootName, FileTreeEntry folder) {
    _items
      ..clear()
      ..add(FileTreeCrumb(path: '', name: rootName));
    if (folder.path.isNotEmpty) push(folder);
  }
}

class FileTreeCrumb {
  final String path;
  final String name;

  const FileTreeCrumb({required this.path, required this.name});
}
