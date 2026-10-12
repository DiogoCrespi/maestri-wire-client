// Layout da barra lateral de workspaces (`SidebarLayout`).
// Contrato: notes/maestri-wire.md, "GET /api/workspaces" (capability workspaceManagement).
// Pastas de nível superior e grupos; cada grupo tem as próprias pastas.

String? _id(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

class SidebarFolder {
  final String id;
  final String name;

  const SidebarFolder({required this.id, required this.name});

  static SidebarFolder? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _id(raw['id']);
    final name = _id(raw['name']);
    if (id == null || name == null) return null;
    return SidebarFolder(id: id, name: name);
  }
}

class SidebarGroup {
  final String id;
  final String name;
  final List<SidebarFolder> folders;

  const SidebarGroup({required this.id, required this.name, this.folders = const []});

  static SidebarGroup? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _id(raw['id']);
    final name = _id(raw['name']);
    if (id == null || name == null) return null;
    return SidebarGroup(
      id: id,
      name: name,
      folders: SidebarLayout._folders(raw['folders']),
    );
  }
}

/// Onde um workspace pode ser arquivado: pastas de nível superior e grupos.
class SidebarLayout {
  final List<SidebarFolder> folders;
  final List<SidebarGroup> groups;

  const SidebarLayout({this.folders = const [], this.groups = const []});

  static const empty = SidebarLayout();

  bool get isEmpty => folders.isEmpty && groups.isEmpty;

  /// Ausente ou malformado vira layout vazio (sem pastas nem grupos).
  factory SidebarLayout.fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final groups = raw['groups'];
    return SidebarLayout(
      folders: _folders(raw['folders']),
      groups: groups is List
          ? [for (final g in groups) if (SidebarGroup.tryFromJson(g) case final SidebarGroup grp) grp]
          : const [],
    );
  }

  static List<SidebarFolder> _folders(Object? raw) => raw is List
      ? [for (final f in raw) if (SidebarFolder.tryFromJson(f) case final SidebarFolder folder) folder]
      : const [];

  /// Procura uma pasta de nível superior ou dentro de um grupo pelo id.
  SidebarFolder? folderById(String id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    for (final g in groups) {
      for (final f in g.folders) {
        if (f.id == id) return f;
      }
    }
    return null;
  }

  SidebarGroup? groupById(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }
}
