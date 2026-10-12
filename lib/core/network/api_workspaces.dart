import '../../models/sidebar_layout.dart';
import '../../models/workspace.dart';
import 'api_floors.dart';
import 'wire_client.dart';

/// Resposta de GET /api/workspaces: os workspaces na ordem da barra lateral e o layout.
class WorkspacesListing {
  final List<WorkspaceMeta> workspaces;
  final SidebarLayout layout;

  const WorkspacesListing({required this.workspaces, this.layout = SidebarLayout.empty});

  factory WorkspacesListing.fromJson(Map<String, dynamic> json) {
    final list = json['workspaces'];
    return WorkspacesListing(
      workspaces: list is List
          ? [
              for (final w in list)
                if (w is Map) WorkspaceMeta.fromJson(Map<String, dynamic>.from(w)),
            ]
          : const [],
      layout: SidebarLayout.fromJson(json['layout']),
    );
  }
}

/// Lugar onde um workspace é arquivado: uma pasta, senão um grupo, senão o nível superior.
class WorkspacePlacement {
  final String? folderId;
  final String? groupId;

  const WorkspacePlacement({this.folderId, this.groupId});

  static const topLevel = WorkspacePlacement();

  Map<String, dynamic> toJson() => {
        if (folderId != null) 'folderId': folderId,
        if (groupId != null) 'groupId': groupId,
      };
}

class DirectoryEntry {
  final String name;
  final String path;

  const DirectoryEntry({required this.name, required this.path});
}

/// `DirectoryListing` de GET /api/directories?path= (pastas do disco do host).
class DirectoryListing {
  final String path;
  final String name;
  final List<DirectoryEntry> directories;
  final bool isTruncated;

  const DirectoryListing({
    required this.path,
    required this.name,
    this.directories = const [],
    this.isTruncated = false,
  });

  factory DirectoryListing.fromJson(Map<String, dynamic> json) {
    final dirs = json['directories'];
    return DirectoryListing(
      path: json['path'] is String ? json['path'] as String : '',
      name: json['name'] is String ? json['name'] as String : '',
      directories: dirs is List
          ? [
              for (final d in dirs)
                if (d is Map && d['name'] is String && d['path'] is String)
                  DirectoryEntry(name: d['name'] as String, path: d['path'] as String),
            ]
          : const [],
      isTruncated: json['isTruncated'] == true,
    );
  }
}

/// Workspaces e barra lateral (owner para escrita).
/// Contrato: notes/maestri-wire.md, "Workspaces e o feed".
extension WorkspacesApi on WireClient {
  String _wsPath(String workspaceId, [String action = '']) =>
      '/api/workspaces/${Uri.encodeComponent(workspaceId)}${action.isEmpty ? '' : '/$action'}';

  /// GET /api/workspaces — workspaces com resumos de andar e o layout da barra lateral.
  Future<WorkspacesListing> listWorkspacesWithLayout() async {
    final json = await hostGetJson(this, '/api/workspaces');
    return WorkspacesListing.fromJson(json);
  }

  /// POST /api/workspaces — Novo Workspace. Retorna o id. 404 quando o diretório
  /// não existe: tente de novo com `createDirectory: true`.
  Future<String> createWorkspace({
    required String name,
    String? icon,
    String? color,
    String? workingDirectory,
    bool createDirectory = false,
    WorkspacePlacement placement = WorkspacePlacement.topLevel,
  }) async {
    final json = await hostRequestJson(this, 'POST', '/api/workspaces', {
      'name': name.trim(),
      if (icon != null && icon.trim().isNotEmpty) 'icon': icon.trim(),
      if (color != null && color.trim().isNotEmpty) 'color': color.trim(),
      if (workingDirectory != null && workingDirectory.trim().isNotEmpty)
        'workingDirectory': workingDirectory.trim(),
      if (createDirectory) 'createDirectory': true,
      if (placement.toJson().isNotEmpty) 'placement': placement.toJson(),
    });
    final id = json['workspaceId'];
    if (id is! String) {
      throw const FloorApiException(
        statusCode: 200,
        code: 'unknown',
        message: 'O host não devolveu o id do workspace criado.',
      );
    }
    return id;
  }

  /// POST …/update — Editar Workspace. Campos `null` ficam como estão (omitidos).
  /// `placement` move o workspace para outra pasta/grupo do layout.
  Future<void> updateWorkspace(
    String workspaceId, {
    String? name,
    String? color,
    String? workingDirectory,
    bool createDirectory = false,
    WorkspacePlacement? placement,
  }) async {
    await hostRequestJson(this, 'POST', _wsPath(workspaceId, 'update'), {
      if (name != null) 'name': name.trim(),
      if (color != null && color.trim().isNotEmpty) 'color': color.trim(),
      if (workingDirectory != null) 'workingDirectory': workingDirectory.trim(),
      if (createDirectory) 'createDirectory': true,
      if (placement != null) 'placement': placement.toJson(),
    });
  }

  /// DELETE /api/workspaces/{ws} — sem confirmação aqui: a confirmação é da UI.
  Future<void> deleteWorkspace(String workspaceId) async {
    await hostRequestJson(this, 'DELETE', _wsPath(workspaceId));
  }

  /// POST …/pin {pinned}. Idempotente.
  Future<void> pinWorkspace(String workspaceId, {required bool pinned}) async {
    await hostRequestJson(this, 'POST', _wsPath(workspaceId, 'pin'), {'pinned': pinned});
  }

  /// POST …/rename {name}. Nome vazio é 400.
  Future<void> renameWorkspace(String workspaceId, String name) async {
    await hostRequestJson(this, 'POST', _wsPath(workspaceId, 'rename'), {'name': name.trim()});
  }

  /// POST …/wake — inicia os terminais sem ativar o workspace no host.
  Future<void> wakeWorkspace(String workspaceId) async {
    await hostRequestJson(this, 'POST', _wsPath(workspaceId, 'wake'));
  }

  /// POST …/unload — para todos os terminais do workspace.
  Future<void> unloadWorkspace(String workspaceId) async {
    await hostRequestJson(this, 'POST', _wsPath(workspaceId, 'unload'));
  }

  /// POST …/attention/clear — limpa o badge de atenção do workspace.
  Future<void> clearWorkspaceAttention(String workspaceId) async {
    await hostRequestJson(this, 'POST', _wsPath(workspaceId, 'attention/clear'));
  }

  /// GET /api/directories?path= (ou ?prefix=) — pastas do disco do host.
  /// `path` "" é a pasta pessoal.
  Future<DirectoryListing> listDirectories({String path = ''}) async {
    final json = await hostGetJson(
      this,
      '/api/directories?path=${Uri.encodeQueryComponent(path)}',
    );
    return DirectoryListing.fromJson(json);
  }
}
