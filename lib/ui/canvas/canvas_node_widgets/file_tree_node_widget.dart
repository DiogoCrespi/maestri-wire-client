import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/canvas_node.dart';
import '../node_card.dart';

/// Árvore de arquivos: a pasta raiz e a contagem quando o host envia.
class FileTreeNodeWidget extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;

  const FileTreeNodeWidget({super.key, required this.node, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final tree = node.payload.isNotEmpty ? node.payload : (node.rawData['fileTree'] as Map?) ?? const {};
    final root = (tree['rootPath'] ?? tree['path'] ?? node.currentDirectory ?? '').toString();
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
                const Icon(Icons.folder_rounded, size: 16, color: AppColors.neonViolet),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    root.isEmpty ? 'Árvore de arquivos' : root,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
