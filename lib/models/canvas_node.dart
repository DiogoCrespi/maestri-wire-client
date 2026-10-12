import 'package:flutter/material.dart';

import 'canvas/cable_tie_group.dart';
import 'canvas/canvas_group.dart';
import 'canvas/connection.dart';
import 'canvas/drawing.dart';

/// Converte "#RRGGBB" ou "#AARRGGBB" em Color. Null para valores inválidos.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  return value == null ? null : Color(value);
}

enum NodeType {
  terminal,
  note,
  noteStack,
  fileTree,
  portal,
  routine,
  text,
  file,
  link,
  connector,
  unknown,
}

enum NodeStatus {
  idle,
  running,
  attention,
  error,
}

/// Representa qualquer nó flutuante presente no Canvas Infinito do Maestri.
class CanvasNode {
  final String id;
  final NodeType type;
  /// Valor literal de `kind` no host (útil para tipos desconhecidos).
  final String kind;
  final String title;
  Offset position;
  Size size;
  final NodeStatus status;
  final String? terminalId;
  final String? previewText;
  final String? currentDirectory;
  final String? gitBranch;
  final Map<String, dynamic> rawData;
  /// Tipo do agente do terminal (claude_code, codex, antigravity_cli, open_code, generic_shell)
  final String? agentType;
  final bool isRunning;
  final bool needsAttention;
  final bool isActive;
  /// `isNodeLocked` do host: não move nem redimensiona.
  final bool isLocked;
  final String? groupId;
  final int zIndex;

  CanvasNode({
    required this.id,
    required this.type,
    this.kind = '',
    required this.title,
    required this.position,
    required this.size,
    this.status = NodeStatus.idle,
    this.terminalId,
    this.previewText,
    this.currentDirectory,
    this.gitBranch,
    this.rawData = const {},
    this.agentType,
    this.isRunning = false,
    this.needsAttention = false,
    this.isActive = false,
    this.isLocked = false,
    this.groupId,
    this.zIndex = 0,
  });

  /// Payload do tipo (ex.: `text`, `file`, `connector`) guardado no próprio nó.
  Map<String, dynamic> get payload {
    final p = rawData[kind];
    return p is Map<String, dynamic> ? p : const {};
  }

  /// Nós que aceitam uma corda (porta de origem ou destino).
  bool get isConnectable =>
      type == NodeType.terminal ||
      type == NodeType.note ||
      type == NodeType.noteStack ||
      type == NodeType.portal ||
      type == NodeType.connector;

  Rect get rect => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  factory CanvasNode.fromJson(Map<String, dynamic> json) {
    NodeType parseType(String? t) {
      switch (t) {
        case 'terminal':
          return NodeType.terminal;
        case 'note':
          return NodeType.note;
        case 'noteStack':
          return NodeType.noteStack;
        case 'fileTree':
          return NodeType.fileTree;
        case 'portal':
          return NodeType.portal;
        case 'routine':
          return NodeType.routine;
        case 'text':
          return NodeType.text;
        case 'file':
          return NodeType.file;
        case 'link':
          return NodeType.link;
        case 'connector':
          return NodeType.connector;
        default:
          return NodeType.unknown;
      }
    }

    final terminalObj = json['terminal'] as Map<String, dynamic>?;

    NodeStatus parseStatus(String? s) {
      switch (s) {
        case 'running':
          return NodeStatus.running;
        case 'attention':
          return NodeStatus.attention;
        case 'error':
          return NodeStatus.error;
        default:
          return NodeStatus.idle;
      }
    }

    final frame = json['frame'] as Map<String, dynamic>?;
    final double x = (frame?['x'] ?? json['x'] as num?)?.toDouble() ?? 100.0;
    final double y = (frame?['y'] ?? json['y'] as num?)?.toDouble() ?? 100.0;
    final double width = (frame?['width'] ?? json['width'] as num?)?.toDouble() ?? 360.0;
    final double height = (frame?['height'] ?? json['height'] as num?)?.toDouble() ?? 260.0;

    final kind = (json['kind'] ?? json['type'] ?? '').toString();

    String? preview;
    final chatPreview = terminalObj?['chatPreview'];
    final chatText = chatPreview is Map && chatPreview['entries'] is List
        ? (chatPreview['entries'] as List)
            .whereType<Map>()
            .where((e) => e['kind'] != 'divider')
            .map((e) => (e['text'] ?? '').toString())
            .where((t) => t.isNotEmpty)
            .join('\n')
        : '';
    if (chatText.isNotEmpty) {
      // Com o chat do host ligado e mensagens, a miniatura mostra as entradas estruturadas
      preview = chatText;
    } else if (json['noteStack'] is Map &&
        ((json['noteStack'] as Map)['front'] is Map) &&
        ((json['noteStack'] as Map)['front'] as Map)['preview'] is List) {
      // Fichário: a prévia é a da página da frente
      preview = (((json['noteStack'] as Map)['front'] as Map)['preview'] as List)
          .map((e) => e.toString())
          .join('\n');
    } else if (json['note'] is Map && (json['note'] as Map)['preview'] is List) {
      // Notas: o card traz as primeiras linhas em texto puro
      preview = ((json['note'] as Map)['preview'] as List).map((e) => e.toString()).join('\n');
    } else if (terminalObj != null && terminalObj['preview'] is List) {
      preview = (terminalObj['preview'] as List).map((e) => e.toString()).join('\n');
    } else if (json[kind] is Map && (json[kind] as Map)['text'] is String) {
      // Bloco de texto: o texto mora no payload do próprio tipo
      preview = (json[kind] as Map)['text'] as String;
    } else {
      final raw = json['preview'] ?? json['lastLine'];
      preview = raw is String ? raw : null;
    }

    final effectiveStatus = parseStatus(
      json['status'] ?? terminalObj?['status'] ?? (terminalObj?['needsAttention'] == true ? 'attention' : null),
    );

    return CanvasNode(
      id: (json['id'] ?? terminalObj?['id'] ?? '').toString(),
      type: parseType(kind),
      kind: kind,
      title: (json['title'] ?? terminalObj?['name'] ?? json['name'] ?? 'Sem Título').toString(),
      position: Offset(x, y),
      size: Size(width, height),
      status: effectiveStatus,
      terminalId: terminalObj?['id'] ?? json['terminalId'] ?? json['id'],
      previewText: preview,
      currentDirectory: json['cwd'] ?? terminalObj?['cwd'],
      gitBranch: json['branch'] ?? terminalObj?['branch'],
      rawData: json,
      agentType: terminalObj?['agentType'] as String?,
      isRunning: terminalObj?['isRunning'] == true,
      needsAttention: terminalObj?['needsAttention'] == true,
      isActive: terminalObj?['isActive'] == true,
      isLocked: json['isNodeLocked'] == true,
      groupId: json['groupId'] as String?,
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Snapshot do canvas de um andar (`canvas` do feed). Lido com o parser próprio do canvas,
/// porque o controlador só guarda nós e cordas.
class CanvasSnapshot {
  final List<CanvasNode> nodes;
  final List<Connection> connections;
  final List<Drawing> drawings;
  final List<CanvasGroup> groups;
  final List<CableTieGroup> ties;
  final double zoom;

  const CanvasSnapshot({
    this.nodes = const [],
    this.connections = const [],
    this.drawings = const [],
    this.groups = const [],
    this.ties = const [],
    this.zoom = 1,
  });

  factory CanvasSnapshot.fromJson(Map<String, dynamic> json) {
    return CanvasSnapshot(
      nodes: [
        for (final e in (json['nodes'] as List? ?? const []))
          if (e is Map<String, dynamic>) CanvasNode.fromJson(e),
      ],
      connections: Connection.listFromJson(json['connections']),
      drawings: Drawing.listFromJson(json['drawings']),
      groups: CanvasGroup.listFromJson(json['groups']),
      ties: CableTieGroup.listFromJson(json['cableTies']),
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
    );
  }
}
