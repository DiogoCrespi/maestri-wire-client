import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/canvas_node.dart';
import '../node_card.dart';

/// Fichário: cartão com a página da frente e a contagem de páginas. Toque abre o fichário.
class NoteStackNodeWidget extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;

  const NoteStackNodeWidget({super.key, required this.node, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final tabs = node.payload['tabs'];
    final pages = tabs is List ? tabs.length : 0;
    return NodeCard(
      node: node,
      isSelected: isSelected,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                node.previewText ?? '',
                overflow: TextOverflow.fade,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.3),
              ),
            ),
            Text(
              pages == 1 ? '1 página' : '$pages páginas',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
