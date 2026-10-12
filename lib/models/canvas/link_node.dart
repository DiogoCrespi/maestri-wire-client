import 'json_values.dart';

/// Payload `link` de um `CanvasNode`.
class LinkNode {
  final String url;
  final String? title;

  const LinkNode({required this.url, this.title});

  factory LinkNode.fromJson(Map<String, dynamic> json) {
    return LinkNode(
      url: readStringOr(json['url'], ''),
      title: readString(json['title']),
    );
  }

  /// Descarta entradas sem `url` não vazia.
  static List<LinkNode> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (readMap(e) case final m?) LinkNode.fromJson(m),
    ].where((l) => l.url.isNotEmpty).toList();
  }
}
