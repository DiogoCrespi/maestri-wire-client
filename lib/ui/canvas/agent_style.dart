import 'package:flutter/material.dart';
import '../../models/canvas_node.dart';

/// Identidade visual de cada tipo de terminal: nome, cor e ícone.
class AgentStyle {
  final String label;
  final Color color;
  final IconData icon;

  const AgentStyle(this.label, this.color, this.icon);

  static AgentStyle of(CanvasNode node) {
    switch (node.agentType) {
      case 'claude_code':
        return const AgentStyle('Claude', Color(0xFFD97757), Icons.auto_awesome_rounded);
      case 'codex':
        return const AgentStyle('Codex', Color(0xFF10A37F), Icons.psychology_rounded);
      case 'antigravity_cli':
        return const AgentStyle('Antigravity', Color(0xFF4C8DFF), Icons.rocket_launch_rounded);
      case 'open_code':
        return const AgentStyle('OpenCode', Color(0xFFF59E0B), Icons.code_rounded);
      case 'generic_shell':
      case null:
        return const AgentStyle('Shell', Color(0xFF9CA3AF), Icons.terminal_rounded);
      default:
        return AgentStyle(node.agentType!, const Color(0xFF9653F4), Icons.smart_toy_rounded);
    }
  }
}

/// Estado do terminal para o cabeçalho do card.
enum TerminalState { attention, working, ready, stopped }

class TerminalStateStyle {
  final String label;
  final Color color;

  const TerminalStateStyle(this.label, this.color);

  static TerminalStateStyle of(CanvasNode node) {
    if (node.needsAttention) {
      return const TerminalStateStyle('Precisa de você', Color(0xFFF59E0B));
    }
    if (!node.isRunning) {
      return const TerminalStateStyle('Parado', Color(0xFF6B7280));
    }
    if (node.isActive) {
      return const TerminalStateStyle('Trabalhando', Color(0xFF3B82F6));
    }
    return const TerminalStateStyle('Pronto', Color(0xFF10B981));
  }
}
