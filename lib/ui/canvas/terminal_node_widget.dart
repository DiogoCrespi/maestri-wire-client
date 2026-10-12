import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/terminal_text.dart';
import '../../models/canvas_node.dart';
import 'agent_style.dart';
import 'node_card.dart';

/// Card do terminal no canvas: identidade do agente, estado, última conversa em
/// blocos legíveis (sem o ruído do TUI) e rodapé com pasta e branch.
class TerminalNodeWidget extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;
  final VoidCallback? onOpenFullscreen;

  const TerminalNodeWidget({
    Key? key,
    required this.node,
    this.isSelected = false,
    this.onOpenFullscreen,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final agent = AgentStyle.of(node);
    final state = TerminalStateStyle.of(node);
    final blocks = _recentBlocks();

    return NodeCard(
      node: node,
      isSelected: isSelected,
      onTap: onOpenFullscreen,
      accent: agent.color,
      highlight: node.needsAttention ? const Color(0xFFF59E0B) : null,
      header: _Header(agent: agent, state: state, title: node.title),
      child: Container(
        color: AppColors.terminalBg,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: blocks.isEmpty
                  ? Center(
                      child: Text(
                        'Sem mensagens ainda',
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                      ),
                    )
                  : ClipRect(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final b in blocks) _buildBlock(b, agent)],
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            _Footer(node: node),
          ],
        ),
      ),
    );
  }

  /// Últimos blocos úteis do preview (mensagens e respostas), do mais antigo ao mais novo.
  List<TerminalBlock> _recentBlocks() {
    final raw = node.previewText;
    if (raw == null || raw.trim().isEmpty) return const [];
    final blocks = terminalPreviewBlocks(raw.split('\n'));
    final visible = blocks.where((b) => b.kind != TerminalBlockKind.status).toList();
    return visible.length > 4 ? visible.sublist(visible.length - 4) : visible;
  }

  Widget _buildBlock(TerminalBlock b, AgentStyle agent) {
    final text = b.text;
    switch (b.kind) {
      case TerminalBlockKind.user:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 260),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF9653F4).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textPrimary, height: 1.3),
              ),
            ),
          ),
        );
      case TerminalBlockKind.agent:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
          ),
        );
      case TerminalBlockKind.status:
      case TerminalBlockKind.raw:
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textMuted),
          ),
        );
    }
  }
}

class _Header extends StatelessWidget {
  final AgentStyle agent;
  final TerminalStateStyle state;
  final String title;

  const _Header({required this.agent, required this.state, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: agent.color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(agent.icon, size: 13, color: agent.color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              Text(
                agent.label,
                style: GoogleFonts.inter(fontSize: 9.5, color: agent.color),
              ),
            ],
          ),
        ),
        _StatePill(state: state),
      ],
    );
  }
}

class _StatePill extends StatelessWidget {
  final TerminalStateStyle state;

  const _StatePill({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: state.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: state.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: state.color),
          ),
          const SizedBox(width: 4),
          Text(
            state.label,
            style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w600, color: state.color),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final CanvasNode node;

  const _Footer({required this.node});

  @override
  Widget build(BuildContext context) {
    final dir = node.currentDirectory?.split('/').last;
    return Row(
      children: [
        if (dir != null) ...[
          const Icon(Icons.folder_open_rounded, size: 11, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              dir,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (node.gitBranch != null) ...[
          const Icon(Icons.alt_route_rounded, size: 11, color: AppColors.textAccent),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              node.gitBranch!,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textAccent),
            ),
          ),
        ],
        const Spacer(),
        Icon(Icons.open_in_full_rounded, size: 12, color: AppColors.textMuted.withValues(alpha: 0.7)),
      ],
    );
  }
}
