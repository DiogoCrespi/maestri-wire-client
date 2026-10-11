/// Metadados de um Workspace no Maestri
class WorkspaceMeta {
  final String id;
  final String name;
  final String? icon;
  final String? color;
  final String? activeFloorId;
  final bool isPinned;
  final int terminalCount;
  final int runningTerminalCount;
  final int attentionCount;
  final bool hasActivity;
  final bool isLoaded;
  final String? workingDirectory;

  WorkspaceMeta({
    required this.id,
    required this.name,
    this.icon,
    this.color,
    this.activeFloorId,
    this.isPinned = false,
    this.terminalCount = 0,
    this.runningTerminalCount = 0,
    this.attentionCount = 0,
    this.hasActivity = false,
    this.isLoaded = true,
    this.workingDirectory,
  });

  factory WorkspaceMeta.fromJson(Map<String, dynamic> json) {
    return WorkspaceMeta(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Sem Título',
      icon: json['icon'],
      color: json['color'],
      activeFloorId: json['activeFloorId'],
      isPinned: json['isPinned'] ?? false,
      terminalCount: json['terminalCount'] ?? 0,
      runningTerminalCount: json['runningTerminalCount'] ?? 0,
      attentionCount: json['attentionCount'] ?? 0,
      hasActivity: json['hasActivity'] ?? false,
      isLoaded: json['isLoaded'] ?? true,
      workingDirectory: json['workingDirectory'],
    );
  }
}

/// Metadados de um Andar (Floor) dentro de um Workspace
class FloorMeta {
  final String? id; // null = térreo (ground)
  final String name;
  final String? color;
  final bool isActive;
  final bool isGitIsolated;
  final String? branch;
  final int attentionCount;
  final bool hasActivity;

  FloorMeta({
    this.id,
    required this.name,
    this.color,
    this.isActive = false,
    this.isGitIsolated = false,
    this.branch,
    this.attentionCount = 0,
    this.hasActivity = false,
  });

  bool get isGround => id == null;

  factory FloorMeta.fromJson(Map<String, dynamic> json) {
    return FloorMeta(
      id: json['id'],
      name: json['name'] ?? 'Térreo',
      color: json['color'],
      isActive: json['isActive'] ?? false,
      isGitIsolated: json['isGitIsolated'] ?? false,
      branch: json['branch'],
      attentionCount: json['attentionCount'] ?? 0,
      hasActivity: json['hasActivity'] ?? false,
    );
  }
}
