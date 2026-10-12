import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/canvas_node.dart';
import '../node_card.dart';

/// Arquivo ou imagem/vídeo do canvas: ícone do tipo, nome e legenda.
class FileNodeWidget extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;

  const FileNodeWidget({super.key, required this.node, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final p = node.payload;
    final isImage = p['isImage'] == true;
    final isVideo = p['isVideo'] == true;
    final name = (p['displayName'] ?? node.title).toString();
    final caption = p['caption'] as String?;
    final icon = isImage
        ? Icons.image_rounded
        : isVideo
            ? Icons.movie_rounded
            : Icons.insert_drive_file_rounded;

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
                Icon(icon, size: 28, color: AppColors.neonViolet),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (caption != null && caption.isNotEmpty) ...[
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  caption,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
