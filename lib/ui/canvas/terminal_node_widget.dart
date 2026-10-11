import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../models/canvas_node.dart';
import 'node_card.dart';

/// Card do Terminal dentro do Canvas Infinito com preview monoespacado estilo macOS Terminal.
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
    return NodeCard(
      node: node,
      isSelected: isSelected,
      onTap: onOpenFullscreen,
      child: Container(
        color: AppColors.terminalBg,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linha com Diretório / Git Branch
            if (node.currentDirectory != null || node.gitBranch != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    if (node.currentDirectory != null) ...[
                      const Icon(Icons.folder_open_rounded,
                          size: 11, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        node.currentDirectory?.split('/').last ?? '',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                    if (node.gitBranch != null) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.alt_route_rounded,
                          size: 11, color: AppColors.textAccent),
                      const SizedBox(width: 3),
                      Text(
                        node.gitBranch ?? '',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: AppColors.textAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            // Linhas de saída do terminal (exibe as linhas mais recentes)
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Builder(
                  builder: (context) {
                    final raw = node.previewText ??
                        '\$ agent running...\n✓ Workspace context ready\nWaiting for next prompt...';
                    final lines = raw.split('\n');
                    final display = lines.length > 7
                        ? lines.sublist(lines.length - 7).join('\n')
                        : raw;
                    return Text(
                      display,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    );
                  },
                ),
              ),
            ),
            // Barra inferior com prompt pronto
            Container(
              padding: const EdgeInsets.only(top: 6),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFF1E212D), width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Text('❯ ',
                      style: TextStyle(
                          color: AppColors.statusActive,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                  const Expanded(
                    child: Text(
                      'Toque para abrir terminal...',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                    ),
                  ),
                  Icon(Icons.open_in_full_rounded,
                      size: 12, color: AppColors.textMuted.withOpacity(0.7)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
