import 'floor.dart';

/// Andar ainda sendo copiado (`PendingFloor`), exibido com progresso no seletor.
class PendingFloor {
  final String id;
  final String name;
  final String? branch;
  final int completedItems;
  final int totalItems;
  final String? error;

  const PendingFloor({
    required this.id,
    required this.name,
    this.branch,
    this.completedItems = 0,
    this.totalItems = 0,
    this.error,
  });

  static PendingFloor? tryFromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    int n(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
    String? s(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    return PendingFloor(
      id: raw['id'] as String,
      name: s(raw['name']) ?? 'Sem Título',
      branch: s(raw['branch']),
      completedItems: n(raw['completedItems']),
      totalItems: n(raw['totalItems']),
      error: s(raw['error']),
    );
  }
}

/// Metadados de um Workspace no Maestri (`WorkspaceMeta`).
///
/// Os campos `floors`, `pendingFloors`, `groundStatus` e `groundFloorBranch`
/// são null quando o host não os enviou: null significa indisponível, não uma
/// lista vazia e autoritativa.
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

  /// Pasta e grupo da barra lateral onde o workspace está (por nome).
  final String? folderName;
  final String? groupName;
  final bool isLocked;

  /// `isActive` do host: reflete o andar do host (na lista) ou o andar visto (no feed).
  final bool isActive;

  /// Ambiente além do host (`{kind, name}`); null para o próprio host.
  final String? environmentKind;
  final String? environmentName;

  final List<FloorMeta>? floors;
  final List<PendingFloor>? pendingFloors;
  final FloorStatus? groundStatus;
  final String? groundFloorBranch;

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
    this.folderName,
    this.groupName,
    this.isLocked = false,
    this.isActive = false,
    this.environmentKind,
    this.environmentName,
    this.floors,
    this.pendingFloors,
    this.groundStatus,
    this.groundFloorBranch,
  });

  factory WorkspaceMeta.fromJson(Map<String, dynamic> json) {
    String? str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    final env = json['environment'];
    final pending = json['pendingFloors'];
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
      folderName: str(json['folderName']),
      groupName: str(json['groupName']),
      isLocked: json['isLocked'] == true,
      isActive: json['isActive'] == true,
      environmentKind: env is Map ? str(env['kind']) : null,
      environmentName: env is Map ? str(env['name']) : null,
      floors: json['floors'] is List ? FloorMeta.listFromJson(json['floors']) : null,
      pendingFloors: pending is List
          ? [for (final p in pending) if (PendingFloor.tryFromJson(p) case final PendingFloor pf) pf]
          : null,
      groundStatus: FloorStatus.tryFromJson(json['groundStatus']),
      groundFloorBranch: str(json['groundFloorBranch']),
    );
  }

  WorkspaceMeta copyWith({bool? isPinned, String? name}) => WorkspaceMeta(
        id: id,
        name: name ?? this.name,
        icon: icon,
        color: color,
        activeFloorId: activeFloorId,
        isPinned: isPinned ?? this.isPinned,
        terminalCount: terminalCount,
        runningTerminalCount: runningTerminalCount,
        attentionCount: attentionCount,
        hasActivity: hasActivity,
        isLoaded: isLoaded,
        workingDirectory: workingDirectory,
        folderName: folderName,
        groupName: groupName,
        isLocked: isLocked,
        isActive: isActive,
        environmentKind: environmentKind,
        environmentName: environmentName,
        floors: floors,
        pendingFloors: pendingFloors,
        groundStatus: groundStatus,
        groundFloorBranch: groundFloorBranch,
      );
}
