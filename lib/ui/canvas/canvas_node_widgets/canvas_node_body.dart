import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/canvas_node.dart';
import '../node_card.dart';
import 'connector_node_widget.dart';
import 'file_node_widget.dart';
import 'file_tree_node_widget.dart';
import 'link_node_widget.dart';
import 'note_node_widget.dart';
import 'note_stack_node_widget.dart';
import 'text_node_widget.dart';

/// Corpo visual dos nós que não são terminal nem portal (esses seguem seus próprios widgets).
/// Tipo desconhecido vira uma caixa simples com título e `kind`.
Widget buildCanvasNodeBody(CanvasNode node, {required bool isSelected}) {
  switch (node.type) {
    case NodeType.text:
      return TextNodeWidget(node: node, isSelected: isSelected);
    case NodeType.file:
      return FileNodeWidget(node: node, isSelected: isSelected);
    case NodeType.link:
      return LinkNodeWidget(node: node, isSelected: isSelected);
    case NodeType.connector:
      return ConnectorNodeWidget(node: node, isSelected: isSelected);
    case NodeType.fileTree:
      return FileTreeNodeWidget(node: node, isSelected: isSelected);
    case NodeType.noteStack:
      return NoteStackNodeWidget(node: node, isSelected: isSelected);
    case NodeType.note:
      return NoteNodeWidget(node: node, isSelected: isSelected);
    case NodeType.terminal:
    case NodeType.portal:
    case NodeType.routine:
    case NodeType.unknown:
      return UnknownNodeWidget(node: node, isSelected: isSelected);
  }
}

/// Caixa simples para tipos que o cliente ainda não desenha (e para `routine`).
class UnknownNodeWidget extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;

  const UnknownNodeWidget({super.key, required this.node, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return NodeCard(
      node: node,
      isSelected: isSelected,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            node.kind.isEmpty ? 'Nó' : node.kind,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ),
      ),
    );
  }
}
