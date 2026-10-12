import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/canvas_node.dart';
import '../node_card.dart';

/// Nota solta: as primeiras linhas do texto, em cartão. Toque abre a nota.
class NoteNodeWidget extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;

  const NoteNodeWidget({super.key, required this.node, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return NodeCard(
      node: node,
      isSelected: isSelected,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          node.previewText ?? '',
          overflow: TextOverflow.fade,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.3),
        ),
      ),
    );
  }
}
