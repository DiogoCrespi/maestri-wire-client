/// Threads do chat de um terminal: sete slots fixos (`0…6`) com cor estável.
/// Presente no snapshot só quando o host suporta threads.
class ChatThreads {
  final int activeSlot;
  final bool canSelect;
  final List<ChatThreadItem> items;

  const ChatThreads({
    required this.activeSlot,
    required this.canSelect,
    required this.items,
  });

  factory ChatThreads.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return ChatThreads(
      activeSlot: (json['activeSlot'] as num?)?.toInt() ?? 0,
      canSelect: json['canSelect'] == true,
      items: raw is List
          ? [
              for (final e in raw)
                if (e is Map<String, dynamic>) ChatThreadItem.fromJson(e),
            ]
          : const [],
    );
  }
}

class ChatThreadItem {
  final int id; // slot 0…6
  final String color; // blue, purple, pink, red, orange, yellow, green, graphite
  final bool hasMessages;

  const ChatThreadItem({required this.id, required this.color, required this.hasMessages});

  factory ChatThreadItem.fromJson(Map<String, dynamic> json) {
    return ChatThreadItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      color: (json['color'] ?? 'blue').toString(),
      hasMessages: json['hasMessages'] == true,
    );
  }
}
