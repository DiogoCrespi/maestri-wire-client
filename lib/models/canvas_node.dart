import 'package:flutter/material.dart';

enum NodeType {
  terminal,
  note,
  fileTree,
  portal,
  routine,
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
  final String title;
  Offset position;
  Size size;
  final NodeStatus status;
  final String? terminalId;
  final String? previewText;
  final String? currentDirectory;
  final String? gitBranch;
  final Map<String, dynamic> rawData;

  CanvasNode({
    required this.id,
    required this.type,
    required this.title,
    required this.position,
    required this.size,
    this.status = NodeStatus.idle,
    this.terminalId,
    this.previewText,
    this.currentDirectory,
    this.gitBranch,
    this.rawData = const {},
  });

  factory CanvasNode.fromJson(Map<String, dynamic> json) {
    NodeType parseType(String? t) {
      switch (t) {
        case 'terminal':
          return NodeType.terminal;
        case 'note':
          return NodeType.note;
        case 'fileTree':
          return NodeType.fileTree;
        case 'portal':
          return NodeType.portal;
        case 'routine':
          return NodeType.routine;
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

    String? preview;
    if (terminalObj != null && terminalObj['preview'] is List) {
      preview = (terminalObj['preview'] as List).map((e) => e.toString()).join('\n');
    } else {
      preview = json['preview'] ?? json['text'] ?? json['lastLine'];
    }

    final effectiveStatus = parseStatus(
      json['status'] ?? terminalObj?['status'] ?? (terminalObj?['needsAttention'] == true ? 'attention' : null),
    );

    return CanvasNode(
      id: json['id'] ?? terminalObj?['id'] ?? '',
      type: parseType(json['kind'] ?? json['type']),
      title: json['title'] ?? terminalObj?['name'] ?? json['name'] ?? 'Sem Título',
      position: Offset(x, y),
      size: Size(width, height),
      status: effectiveStatus,
      terminalId: terminalObj?['id'] ?? json['terminalId'] ?? json['id'],
      previewText: preview,
      currentDirectory: json['cwd'] ?? terminalObj?['cwd'],
      gitBranch: json['branch'] ?? terminalObj?['branch'],
      rawData: json,
    );
  }
}
