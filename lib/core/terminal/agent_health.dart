/// Diagnóstico de um terminal de agente a partir da saída recente do shell.
///
/// O host digita o comando do agente dentro do shell. Se o binário não existe,
/// o shell imprime "comando não encontrado" e o terminal fica num prompt, sem
/// nenhum aviso. Esta função transforma essa saída em um diagnóstico.
enum AgentIssueKind { none, agentNotInstalled, maestriMissing }

class AgentIssue {
  final AgentIssueKind kind;
  /// Nome do comando que não foi encontrado (ex.: `agy`), quando detectado.
  final String? command;

  const AgentIssue(this.kind, {this.command});

  static const none = AgentIssue(AgentIssueKind.none);

  bool get hasIssue => kind != AgentIssueKind.none;
}

final _notFound = RegExp(
  r'(?:bash|zsh|sh):\s*(?:linha \d+:\s*)?([^\s:]+):\s*(?:comando não encontrado|command not found)',
);

/// Analisa as linhas mais recentes do terminal (da mais antiga para a mais nova).
/// Considera só as últimas [window] linhas, para não reagir a erros antigos.
AgentIssue detectAgentIssue(List<String> lines, {int window = 40}) {
  final recent = lines.length > window ? lines.sublist(lines.length - window) : lines;
  // O mais recente vence: se o problema foi resolvido depois, não avisa.
  for (final line in recent.reversed) {
    final m = _notFound.firstMatch(line);
    if (m != null) {
      final cmd = m.group(1)!;
      if (cmd == 'maestri') return const AgentIssue(AgentIssueKind.maestriMissing, command: 'maestri');
      return AgentIssue(AgentIssueKind.agentNotInstalled, command: cmd);
    }
    if (line.contains('comando não encontrado') || line.contains('command not found')) {
      return const AgentIssue(AgentIssueKind.agentNotInstalled);
    }
  }
  return AgentIssue.none;
}

/// Texto curto para o usuário, em português.
String agentIssueMessage(AgentIssue issue, {required String agentName}) {
  switch (issue.kind) {
    case AgentIssueKind.agentNotInstalled:
      final cmd = issue.command;
      return cmd == null
          ? '$agentName não foi encontrado no host. O terminal está num shell comum. '
              'Instale o agente ou recrie o terminal com outro preset.'
          : 'O comando "$cmd" não foi encontrado no host. O terminal caiu para o shell. '
              'Instale o $agentName ou recrie o terminal com outro preset.';
    case AgentIssueKind.maestriMissing:
      return 'O CLI "maestri" não está no ambiente deste terminal. Terminais criados antes do modo Maestro '
          'precisam ser recriados (ou reiniciados) para receber o ambiente.';
    case AgentIssueKind.none:
      return '';
  }
}
