import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/chat_attachment.dart';

/// Anexos preparados que vão no próximo envio. Cada um sai com o x (remove no host).
class ChatPendingAttachments extends StatelessWidget {
  final List<ChatAttachment> items;
  final ValueChanged<ChatAttachment> onRemove;

  const ChatPendingAttachments({super.key, required this.items, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final a in items)
            InputChip(
              avatar: Icon(
                a.isImage ? Icons.image_outlined : Icons.attach_file_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              label: Text(a.fileName, style: const TextStyle(fontSize: 12)),
              backgroundColor: AppColors.surfaceHover,
              side: const BorderSide(color: AppColors.border),
              onDeleted: () => onRemove(a),
            ),
        ],
      ),
    );
  }
}
