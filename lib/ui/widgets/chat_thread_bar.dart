import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/chat_thread.dart';

/// Cor de uma thread pela chave que o host manda. A ordem e as cores são fixas.
Color chatThreadColor(String key) {
  switch (key) {
    case 'purple':
      return const Color(0xFFBF5AF2);
    case 'pink':
      return const Color(0xFFFF375F);
    case 'red':
      return const Color(0xFFFF453A);
    case 'orange':
      return const Color(0xFFFF9F0A);
    case 'yellow':
      return const Color(0xFFFFD60A);
    case 'green':
      return const Color(0xFF30D158);
    case 'graphite':
      return const Color(0xFF8E8E93);
    case 'blue':
    default:
      return const Color(0xFF0A84FF);
  }
}

/// Sete bolinhas de thread. Toque seleciona (se `canSelect`); toque longo limpa
/// a thread quando ela tem mensagens.
class ChatThreadBar extends StatelessWidget {
  final ChatThreads threads;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClear;

  const ChatThreadBar({
    super.key,
    required this.threads,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: threads.items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final item = threads.items[i];
          final selected = item.id == threads.activeSlot;
          final color = chatThreadColor(item.color);
          return Tooltip(
            message: 'Thread ${item.id + 1}${item.hasMessages ? '' : ' (vazia)'}',
            child: GestureDetector(
              onTap: threads.canSelect && !selected ? () => onSelect(item.id) : null,
              onLongPress: threads.canSelect && item.hasMessages ? () => onClear(item.id) : null,
              child: Opacity(
                opacity: threads.canSelect || selected ? 1 : 0.5,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: item.hasMessages ? color.withValues(alpha: 0.85) : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.textPrimary : color,
                      width: selected ? 2 : 1.5,
                    ),
                  ),
                  child: Text(
                    '${item.id + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: item.hasMessages ? Colors.white : color,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
