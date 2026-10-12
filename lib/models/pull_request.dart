// Pull request do andar: contexto para abrir, agentes para perguntar e os
// valores fixos das rotas. Contrato: notes/maestri-wire.md, "Andares",
// "pull-request/*" e "FloorPullRequest".

/// Métodos de merge que o cliente conhece. O host diz quais oferece agora
/// (`mergeMethods`); um método não oferecido é 409.
const pullRequestMergeMethods = ['merge', 'squash', 'rebase'];

String pullRequestMergeLabel(String method) {
  switch (method) {
    case 'merge':
      return 'Merge';
    case 'squash':
      return 'Squash';
    case 'rebase':
      return 'Rebase';
    default:
      return method;
  }
}

/// Tarefas de Perguntar a um Agente. `assess` só vale num andar de revisão.
const pullRequestTasks = ['review', 'checks', 'conflicts', 'assess'];

String pullRequestTaskLabel(String task) {
  switch (task) {
    case 'review':
      return 'Revisar';
    case 'checks':
      return 'Corrigir checks';
    case 'conflicts':
      return 'Resolver conflitos';
    case 'assess':
      return 'Avaliar revisão';
    default:
      return task;
  }
}

/// Agente do andar que pode receber a pergunta.
class PullRequestAgent {
  final String id;
  final String name;
  final bool isRunning;

  const PullRequestAgent({required this.id, required this.name, this.isRunning = false});

  static PullRequestAgent? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final name = raw['name'];
    return PullRequestAgent(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : 'Agente',
      isRunning: raw['isRunning'] == true,
    );
  }
}

/// `GET …/pull-request/context`: título e descrição pré-preenchidos, o provedor,
/// por que não pode abrir agora e os agentes do andar.
class PullRequestContext {
  final String title;
  final String body;
  final String base;
  final String? providerName;
  final String? account;
  final bool supportsDraft;
  final int? unpushedCommits;

  /// Por que não pode abrir agora (texto do host), ou null.
  final String? problem;
  final List<PullRequestAgent> agents;

  const PullRequestContext({
    required this.title,
    required this.body,
    required this.base,
    this.providerName,
    this.account,
    this.supportsDraft = false,
    this.unpushedCommits,
    this.problem,
    this.agents = const [],
  });

  factory PullRequestContext.fromJson(Map<String, dynamic> json) {
    String str(Object? v) => v is String ? v : '';
    String? opt(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    final commits = json['unpushedCommits'];
    final agents = json['agents'];
    return PullRequestContext(
      title: str(json['title']),
      body: str(json['body']),
      base: str(json['base']),
      providerName: opt(json['providerName']),
      account: opt(json['account']),
      supportsDraft: json['supportsDraft'] == true,
      unpushedCommits: commits is num ? commits.toInt() : null,
      problem: opt(json['problem']),
      agents: agents is List
          ? [for (final a in agents) if (PullRequestAgent.tryFromJson(a) case final PullRequestAgent agent) agent]
          : const [],
    );
  }
}

/// Resposta de POST …/pull-request: a URL para abrir (nunca no host do Maestri).
class PullRequestOpened {
  final String? url;
  final bool openedOnWebsite;

  const PullRequestOpened({this.url, this.openedOnWebsite = false});

  factory PullRequestOpened.fromJson(Map<String, dynamic> json) => PullRequestOpened(
        url: json['url'] is String ? json['url'] as String : null,
        openedOnWebsite: json['openedOnWebsite'] == true,
      );
}

/// Resposta de POST …/pull-request/remove.
class PullRequestRemoved {
  final String? branch;
  final String? mergedInto;

  const PullRequestRemoved({this.branch, this.mergedInto});

  factory PullRequestRemoved.fromJson(Map<String, dynamic> json) => PullRequestRemoved(
        branch: json['branch'] is String ? json['branch'] as String : null,
        mergedInto: json['mergedInto'] is String ? json['mergedInto'] as String : null,
      );
}

/// Corpo de POST …/pull-request. Campos opcionais ausentes são omitidos.
Map<String, dynamic> pullRequestOpenBody({
  required String base,
  required String title,
  required String body,
  bool? draft,
  bool? onWebsite,
}) =>
    {
      'base': base.trim(),
      'title': title.trim(),
      'body': body,
      if (draft != null) 'draft': draft,
      if (onWebsite != null) 'onWebsite': onWebsite,
    };
