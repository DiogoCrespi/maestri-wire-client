import 'json_values.dart';

/// Payload `file` de um `CanvasNode`.
class FileNode {
  final String displayName;
  final String? caption;
  final bool isImage;
  final bool isVideo;

  const FileNode({
    this.displayName = '',
    this.caption,
    this.isImage = false,
    this.isVideo = false,
  });

  factory FileNode.fromJson(Map<String, dynamic> json) {
    return FileNode(
      displayName: readStringOr(json['displayName'], ''),
      caption: readString(json['caption']),
      isImage: readBoolOr(json['isImage'], false),
      isVideo: readBoolOr(json['isVideo'], false),
    );
  }

  /// Entradas que não são objeto são descartadas.
  static List<FileNode> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (readMap(e) case final m?) FileNode.fromJson(m),
    ];
  }
}
