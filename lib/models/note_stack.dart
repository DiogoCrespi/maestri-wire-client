// Fichário (note stack) do canvas: nó `noteStack` do CanvasSnapshot e as respostas
// das rotas de fichário (`stack/front`, `stack/order`, `stack/pages`, `note-stacks`).
//
// Um fichário é um nó de canvas cujas páginas são notas. Notas arquivadas
// continuam endereçáveis por id de nó, mas não aparecem em `tabs`.

/// Cores de nota aceitas pelo host (mesma paleta das threads de chat).
const List<String> kNoteColorKeys = [
  'yellow',
  'blue',
  'purple',
  'pink',
  'red',
  'orange',
  'green',
  'graphite',
];

class NoteStackTab {
  final String nodeId;
  final String title;
  final String? color;

  const NoteStackTab({required this.nodeId, required this.title, this.color});

  factory NoteStackTab.fromJson(Map<String, dynamic> json) {
    return NoteStackTab(
      nodeId: (json['nodeId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      color: json['color'] as String?,
    );
  }
}

/// Resposta de `stack/front`, `stack/order`, `stack/pages/{id}` (PUT/DELETE):
/// `{ok, memberNodeIds, frontNoteId?}`.
class NoteStackRail {
  final List<String> memberNodeIds;
  final String? frontNoteId;

  const NoteStackRail({required this.memberNodeIds, this.frontNoteId});

  factory NoteStackRail.fromJson(Map<String, dynamic> json) {
    final members = json['memberNodeIds'];
    return NoteStackRail(
      memberNodeIds: members is List ? members.map((e) => e.toString()).toList() : const [],
      frontNoteId: json['frontNoteId'] as String?,
    );
  }
}

class NoteStack {
  final String nodeId;
  final String name;
  final bool hasCustomName;
  final List<NoteStackTab> tabs;
  final String? frontNoteId;
  final String? frontTitle;
  final String? frontColor;
  final bool? uniformColor;

  const NoteStack({
    required this.nodeId,
    required this.name,
    required this.hasCustomName,
    required this.tabs,
    this.frontNoteId,
    this.frontTitle,
    this.frontColor,
    this.uniformColor,
  });

  /// Lê um nó do CanvasSnapshot. Retorna null se o nó não for `noteStack`.
  static NoteStack? fromCanvasNode(Map<String, dynamic> node) {
    if (node['kind'] != 'noteStack') return null;
    final payload = node['noteStack'];
    if (payload is! Map<String, dynamic>) return null;
    final tabsRaw = payload['tabs'];
    final tabs = tabsRaw is List
        ? tabsRaw
            .whereType<Map<String, dynamic>>()
            .map(NoteStackTab.fromJson)
            .toList()
        : <NoteStackTab>[];
    final front = payload['front'];
    final frontMap = front is Map<String, dynamic> ? front : null;
    return NoteStack(
      nodeId: (node['id'] ?? '').toString(),
      name: (payload['name'] ?? node['title'] ?? '').toString(),
      hasCustomName: payload['hasCustomName'] == true,
      tabs: tabs,
      frontNoteId: payload['frontNoteId'] as String?,
      frontTitle: frontMap == null
          ? null
          : (frontMap['displayName'] ?? frontMap['fileName'])?.toString(),
      frontColor: frontMap?['color'] as String?,
      uniformColor: payload['uniformColor'] as bool?,
    );
  }

  /// Título para mostrar: o nome do fichário quando ele tem nome próprio; senão a
  /// página da frente (o `name` sem nome próprio pode ser o do andar, ex. "Térreo").
  String get displayTitle {
    if (hasCustomName && name.isNotEmpty) return name;
    final front = frontTitle;
    if (front != null && front.isNotEmpty) return front;
    return name;
  }

  /// Aplica uma resposta de rota de fichário: reordena as abas pelos membros
  /// e atualiza a frente. Abas que saíram do fichário são removidas.
  NoteStack withRail(NoteStackRail rail) {
    final byId = {for (final t in tabs) t.nodeId: t};
    final ordered = <NoteStackTab>[
      for (final id in rail.memberNodeIds)
        if (byId[id] != null) byId[id]!,
    ];
    return NoteStack(
      nodeId: nodeId,
      name: name,
      hasCustomName: hasCustomName,
      tabs: ordered,
      frontNoteId: rail.frontNoteId,
      frontTitle: frontTitle,
      frontColor: frontColor,
      uniformColor: uniformColor,
    );
  }

  NoteStack withTabColor(String noteId, String color) {
    return NoteStack(
      nodeId: nodeId,
      name: name,
      hasCustomName: hasCustomName,
      tabs: [
        for (final t in tabs)
          t.nodeId == noteId ? NoteStackTab(nodeId: t.nodeId, title: t.title, color: color) : t,
      ],
      frontNoteId: frontNoteId,
      frontTitle: frontTitle,
      frontColor: frontColor,
      uniformColor: uniformColor,
    );
  }
}

/// Uma nota que pode ser trazida para um fichário ou escolhida numa seleção:
/// vem de `items` do feed (`kind: note`), inclusive as arquivadas em outros fichários.
class NoteCandidate {
  final String nodeId;
  final String title;
  final String? color;
  final String? floorName;

  const NoteCandidate({
    required this.nodeId,
    required this.title,
    this.color,
    this.floorName,
  });

  /// Lê um `FeedItem` `{kind: note, note: NoteCard}`. Retorna null para outros tipos.
  static NoteCandidate? fromFeedItem(Map<String, dynamic> item) {
    if (item['kind'] != 'note') return null;
    final note = item['note'];
    if (note is! Map<String, dynamic>) return null;
    final nodeId = (note['nodeId'] ?? '').toString();
    if (nodeId.isEmpty) return null;
    final custom = note['hasCustomName'] == true || note['isExternal'] == true;
    final name = (note['displayName'] ?? note['fileName'] ?? '').toString();
    final preview = note['preview'];
    final firstLine = preview is List && preview.isNotEmpty ? preview.first.toString() : '';
    return NoteCandidate(
      nodeId: nodeId,
      // O host só mostra o nome quando ele é próprio; senão a primeira linha.
      title: custom && name.isNotEmpty ? name : (firstLine.isNotEmpty ? firstLine : name),
      color: note['color'] as String?,
      floorName: note['floorName'] as String?,
    );
  }
}

/// Mutações do feed (`MutationEvent.kind`) que mudam uma nota ou um fichário já abertos.
/// [watched] são os ids de nó que a tela mostra (o fichário e/ou suas páginas, ou a nota).
///
/// `noteStackRailChanged` vale quando o fichário ou alguma página entra/sai dele.
/// `nodeLockChanged` e a trava de conteúdo não chegam como mutação: quem recebe o feed
/// deve empurrar `{'kind': 'feedSnapshot'}` para as telas a cada snapshot (ver [kNoteFeedSnapshotKind]).
const String kNoteFeedSnapshotKind = 'feedSnapshot';

bool isNoteRemoteChange(Map<String, dynamic> kind, Set<String> watched) {
  final type = kind['kind'];
  switch (type) {
    case 'noteStackRailChanged':
      if (watched.contains(kind['stackNodeId'])) return true;
      final members = kind['memberNodeIds'];
      return members is List && members.any((m) => watched.contains(m));
    case 'noteColorChanged':
    case 'nodeRemoved':
    case 'nodeLockChanged':
      return watched.contains(kind['nodeId']);
    case 'nodeRenamed':
      final ids = kind['nodeIds'];
      return ids is List && ids.any((m) => watched.contains(m));
    case kNoteFeedSnapshotKind:
      return true;
  }
  return false;
}
