/// Anexo preparado no host para o próximo envio (`POST …/attachments`).
/// Vale 15 minutos e até 8 MiB; o `attachmentId` é o que vai nos segmentos do prompt.
class ChatAttachment {
  final String attachmentId;
  final String fileName;
  final String mimeType;
  final DateTime? expiresAt;

  const ChatAttachment({
    required this.attachmentId,
    required this.fileName,
    required this.mimeType,
    this.expiresAt,
  });

  bool get isImage => mimeType.startsWith('image/');

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      attachmentId: (json['attachmentId'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      mimeType: (json['mimeType'] ?? '').toString(),
      expiresAt: DateTime.tryParse((json['expiresAt'] ?? '').toString()),
    );
  }
}

/// Anexo já guardado numa entrada do chat (`segments` do usuário, `{"attachment":{…}}`).
/// Não carrega caminho do host nem token de staging.
class ChatEntryAttachment {
  final String id;
  final String filename;
  final String contentType; // identificador de tipo do host, ex. public.png
  final bool isImage;

  const ChatEntryAttachment({
    required this.id,
    required this.filename,
    required this.contentType,
    this.isImage = false,
  });

  factory ChatEntryAttachment.fromJson(Map<String, dynamic> json) {
    return ChatEntryAttachment(
      id: (json['id'] ?? '').toString(),
      filename: (json['filename'] ?? '').toString(),
      contentType: (json['contentType'] ?? '').toString(),
      isImage: json['isImage'] == true,
    );
  }
}

/// Segmento de um prompt: `{text}` ou `{attachmentId}`, na ordem do compositor.
sealed class PromptSegment {
  const PromptSegment();

  Map<String, dynamic> toJson();
}

class TextSegment extends PromptSegment {
  final String text;
  const TextSegment(this.text);

  @override
  Map<String, dynamic> toJson() => {'text': text};
}

class AttachmentSegment extends PromptSegment {
  final String attachmentId;
  const AttachmentSegment(this.attachmentId);

  @override
  Map<String, dynamic> toJson() => {'attachmentId': attachmentId};
}
