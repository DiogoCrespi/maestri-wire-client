import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/canvas_node.dart';
import '../node_card.dart';

/// Link salvo no canvas: título e endereço.
class LinkNodeWidget extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;

  const LinkNodeWidget({super.key, required this.node, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final url = (node.payload['url'] ?? '').toString();
    final title = (node.payload['title'] ?? node.title).toString();
    return NodeCard(
      node: node,
      isSelected: isSelected,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link_rounded, size: 16, color: AppColors.neonCobalt),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textAccent, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
