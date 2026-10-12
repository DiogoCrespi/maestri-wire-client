import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../models/terminal_chat.dart';

/// Uma entrada do chat: mensagem do usuário, resposta do agente, progresso ou divisor.
/// `onLongPress` (excluir a entrada) fica de fora nos divisores.
class ChatEntryBubble extends StatelessWidget {
  final ChatEntry entry;
  final VoidCallback? onLongPress;

  const ChatEntryBubble({super.key, required this.entry, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    switch (entry.kind) {
      case ChatEntryKind.divider:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Expanded(child: Divider(color: AppColors.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(entry.text,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
              const Expanded(child: Divider(color: AppColors.border)),
            ],
          ),
        );
      case ChatEntryKind.progress:
        return GestureDetector(
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top_rounded, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    entry.text,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case ChatEntryKind.message:
      case ChatEntryKind.finalAnswer:
      case ChatEntryKind.other:
        return entry.isUser ? _userBubble() : _agentBubble();
    }
  }

  Widget _userBubble() {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.neonViolet.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.text.isNotEmpty)
                SelectableText(
                  entry.text,
                  style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: AppColors.textPrimary),
                ),
              for (final a in entry.attachments)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(a.isImage ? Icons.image_outlined : Icons.attach_file_rounded,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(a.filename,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agentBubble() {
    final author = entry.authorName;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(right: 24, bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology_rounded, size: 14, color: AppColors.textAccent),
                const SizedBox(width: 6),
                Text(author == null || author.isEmpty ? 'Agente' : author,
                    style: const TextStyle(
                        color: AppColors.textAccent, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              entry.text,
              style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
