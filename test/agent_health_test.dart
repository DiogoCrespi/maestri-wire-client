import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/terminal/agent_health.dart';

void main() {
  test('detecta agente não instalado e o nome do comando', () {
    final issue = detectAgentIssue([
      'debian@DCX:~/Documentos\$ agy',
      'bash: agy: comando não encontrado',
      'debian@DCX:~/Documentos\$ ',
    ]);
    expect(issue.kind, AgentIssueKind.agentNotInstalled);
    expect(issue.command, 'agy');
    expect(issue.hasIssue, isTrue);
  });

  test('detecta maestri ausente como problema de ambiente', () {
    final issue = detectAgentIssue([
      'Ran 1 shell command',
      '● /bin/bash: linha 1: maestri: comando não encontrado',
    ]);
    expect(issue.kind, AgentIssueKind.maestriMissing);
    expect(issue.command, 'maestri');
  });

  test('reconhece a mensagem em inglês', () {
    final issue = detectAgentIssue(['zsh: command not found: agy']);
    expect(issue.hasIssue, isTrue);
  });

  test('sem erro recente não há diagnóstico', () {
    expect(detectAgentIssue(['❯ oi', '• Oi! Estou aqui.']).hasIssue, isFalse);
  });

  test('o erro mais recente vence e erros antigos fora da janela são ignorados', () {
    final resolved = detectAgentIssue([
      'bash: agy: comando não encontrado',
      'debian@DCX:~\$ codex',
      '? for shortcuts',
    ]);
    expect(resolved.kind, AgentIssueKind.agentNotInstalled); // ainda é o último erro
    final old = detectAgentIssue(
      ['bash: agy: comando não encontrado', ...List.filled(60, 'linha normal')],
      window: 40,
    );
    expect(old.hasIssue, isFalse);
  });

  test('mensagem para o usuário cita o comando e o agente', () {
    final msg = agentIssueMessage(
      const AgentIssue(AgentIssueKind.agentNotInstalled, command: 'agy'),
      agentName: 'Antigravity',
    );
    expect(msg, contains('"agy"'));
    expect(msg, contains('caiu para o shell'));
  });
}
