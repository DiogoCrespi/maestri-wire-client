// Modelos de andar (floor) do protocolo Maestri Wire.
// Contrato: "## Andares" e "Status do andar e resumos da barra lateral".
//
// Compatível com a API de `FloorMeta` de `workspace.dart` (mesmos nomes e
// `fromJson`), acrescida de status, PR e atenção. Quando integrado, o
// `FloorMeta` de `workspace.dart` deve sair e este arquivo passar a ser a fonte.

String? _text(Object? raw) {
  if (raw is! String) return null;
  final t = raw.trim();
  return t.isEmpty ? null : t;
}

/// Relato do andar (`FloorStatus`). Estados desconhecidos são preservados como
/// vieram do host; o cliente mostra o texto e um marcador neutro.
class FloorStatus {
  static const working = 'working';
  static const blocked = 'blocked';
  static const review = 'review';
  static const done = 'done';
  static const knownStates = {working, blocked, review, done};

  final String state;
  final String text;

  /// Fração em 0…1. Valores fora disso ou não finitos viram null.
  final double? progress;
  final String? author;

  const FloorStatus({
    required this.state,
    required this.text,
    this.progress,
    this.author,
  });

  bool get isKnownState => knownStates.contains(state);

  /// Null quando não há status utilizável (ausente, nulo ou sem texto).
  static FloorStatus? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = _text(raw['text']);
    if (text == null) return null;
    final p = raw['progress'];
    double? progress;
    if (p is num && p.toDouble().isFinite && p >= 0 && p <= 1) {
      progress = p.toDouble();
    }
    return FloorStatus(
      state: _text(raw['state']) ?? 'unknown',
      text: text,
      progress: progress,
      author: _text(raw['author']),
    );
  }
}

/// Pull request ao qual o branch do andar está ligado (`FloorPullRequest`).
class FloorPullRequest {
  /// `open`, `merged` ou `closed`; null enquanto o host não o leu.
  final String? state;
  final bool isDraft;
  final int? number;

  /// `conflicts`, `checksFailing`, `changesRequested`, `approved`,
  /// `checksRunning`, ou outro valor que o cliente deve ignorar.
  final String? attention;
  final String? url;
  final String? title;
  final bool isReview;
  final bool isReadOnly;

  const FloorPullRequest({
    this.state,
    this.isDraft = false,
    this.number,
    this.attention,
    this.url,
    this.title,
    this.isReview = false,
    this.isReadOnly = false,
  });

  static FloorPullRequest? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final n = raw['number'];
    return FloorPullRequest(
      state: _text(raw['state']),
      isDraft: raw['isDraft'] == true,
      number: n is int ? n : null,
      attention: _text(raw['attention']),
      url: _text(raw['url']),
      title: _text(raw['title']),
      isReview: raw['isReview'] == true,
      isReadOnly: raw['isReadOnly'] == true,
    );
  }
}

/// Um andar do workspace. `id == null` é o térreo (ground).
class FloorMeta {
  final String? id;
  final String name;
  final String? color;
  final bool isActive;
  final bool isGitIsolated;
  final String? branch;
  final bool isRemoving;
  final int attentionCount;
  final bool hasActivity;
  final bool isDormant;
  final FloorStatus? status;
  final FloorPullRequest? pullRequest;

  const FloorMeta({
    this.id,
    required this.name,
    this.color,
    this.isActive = false,
    this.isGitIsolated = false,
    this.branch,
    this.isRemoving = false,
    this.attentionCount = 0,
    this.hasActivity = false,
    this.isDormant = false,
    this.status,
    this.pullRequest,
  });

  bool get isGround => id == null;

  /// Valor do parâmetro `floor` das rotas: o UUID do andar, ou `ground`.
  String get queryValue => id ?? 'ground';

  factory FloorMeta.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : null;
    final attention = json['attentionCount'];
    return FloorMeta(
      id: id,
      name: _text(json['name']) ?? (id == null ? 'Térreo' : 'Sem Título'),
      color: _text(json['color']),
      isActive: json['isActive'] == true,
      isGitIsolated: json['isGitIsolated'] == true,
      branch: _text(json['branch']),
      isRemoving: json['isRemoving'] == true,
      attentionCount: attention is int ? attention : 0,
      hasActivity: json['hasActivity'] == true,
      isDormant: json['isDormant'] == true,
      status: FloorStatus.tryFromJson(json['status']),
      pullRequest: FloorPullRequest.tryFromJson(json['pullRequest']),
    );
  }

  /// Lista tolerante: ausente ou malformada vira lista vazia; entradas que não
  /// são objetos são ignoradas.
  static List<FloorMeta> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) FloorMeta.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  /// Ordem de exibição do contrato: andares reais do mais novo ao mais antigo,
  /// e o térreo por último. O host envia o térreo primeiro e depois do mais
  /// antigo ao mais novo.
  static List<FloorMeta> displayOrder(Iterable<FloorMeta> floors) {
    final real = floors.where((f) => !f.isGround).toList().reversed;
    final ground = floors.where((f) => f.isGround);
    return [...real, ...ground];
  }
}
