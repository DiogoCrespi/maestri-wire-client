import 'chat_attachment.dart';
import 'chat_thread.dart';

/// Chat estruturado de um terminal (capability `terminalChat`).
///
/// Diferente da saída crua do PTY, aqui cada mensagem já vem classificada pelo host:
/// `role` (user/agent), `kind` (message, progress, final, divider) e `text` canônico.
/// Por isso a resposta final e o status de trabalho não precisam ser separados da tela.
class ChatSnapshot {
  final String terminalId;
  final String conversationId;
  final bool enabled;
  final String status; // idle, working, needsAttention, notRunning, unloaded
  final List<ChatEntry> entries; // cauda ao vivo, da mais antiga para a mais nova
  final int unreadCount;
  final bool hasOlderOnRecord;
  final bool turnInterrupted;
  final bool canClear;
  final bool showsShellWindow;
  final ChatThreads? threads;
  final String? talkingToAgentName;
  final String? answeringAgentName;

  const ChatSnapshot({
    required this.terminalId,
    required this.conversationId,
    required this.enabled,
    required this.status,
    required this.entries,
    this.unreadCount = 0,
    this.hasOlderOnRecord = false,
    this.turnInterrupted = false,
    this.canClear = true,
    this.showsShellWindow = true,
    this.threads,
    this.talkingToAgentName,
    this.answeringAgentName,
  });

  bool get isWorking => status == 'working';

  factory ChatSnapshot.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final rawThreads = json['threads'];
    return ChatSnapshot(
      terminalId: (json['terminalId'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? '').toString(),
      enabled: json['enabled'] == true,
      status: (json['status'] ?? 'idle').toString(),
      entries: rawEntries is List
          ? [
              for (final e in rawEntries)
                if (e is Map<String, dynamic>) ChatEntry.fromJson(e),
            ]
          : const [],
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      hasOlderOnRecord: json['hasOlderOnRecord'] == true,
      turnInterrupted: json['turnInterrupted'] == true,
      canClear: json['canClear'] != false,
      // Ausente significa um host antigo, que sempre abria a janela do shell
      showsShellWindow: json['showsShellWindow'] != false,
      threads: rawThreads is Map<String, dynamic> ? ChatThreads.fromJson(rawThreads) : null,
      talkingToAgentName: json['talkingToAgentName'] as String?,
      answeringAgentName: json['answeringAgentName'] as String?,
    );
  }
}

class ChatEntry {
  final String id;
  final bool isUser; // role == user
  final DateTime? timestamp;
  final ChatEntryKind kind;
  final String text;
  final String? authorName;
  final String? clientMessageId;
  final List<ChatEntryAttachment> attachments;

  const ChatEntry({
    required this.id,
    required this.isUser,
    required this.kind,
    required this.text,
    this.timestamp,
    this.authorName,
    this.clientMessageId,
    this.attachments = const [],
  });

  factory ChatEntry.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'];
    final attachments = <ChatEntryAttachment>[];
    if (rawSegments is List) {
      for (final s in rawSegments) {
        if (s is Map && s['attachment'] is Map) {
          attachments.add(ChatEntryAttachment.fromJson(
              Map<String, dynamic>.from(s['attachment'] as Map)));
        }
      }
    }
    return ChatEntry(
      id: (json['id'] ?? '').toString(),
      isUser: json['role'] == 'user',
      timestamp: DateTime.tryParse((json['ts'] ?? '').toString()),
      kind: ChatEntryKind.parse(json['kind']?.toString()),
      text: (json['text'] ?? '').toString(),
      authorName: json['authorName'] as String?,
      clientMessageId: json['clientMessageId'] as String?,
      attachments: attachments,
    );
  }
}

/// Tipos de entrada. Valores desconhecidos viram [other], como o contrato pede.
enum ChatEntryKind {
  message,
  progress,
  finalAnswer,
  divider,
  other;

  static ChatEntryKind parse(String? raw) {
    switch (raw) {
      case 'message':
        return ChatEntryKind.message;
      case 'progress':
        return ChatEntryKind.progress;
      case 'final':
        return ChatEntryKind.finalAnswer;
      case 'divider':
        return ChatEntryKind.divider;
      default:
        return ChatEntryKind.other;
    }
  }
}
