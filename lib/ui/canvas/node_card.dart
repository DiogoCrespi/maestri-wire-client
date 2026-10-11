import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/mac_theme.dart';
import '../../models/canvas_node.dart';

/// Card flutuante genérico no Canvas Infinito com visual macOS
class NodeCard extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget child;

  const NodeCard({
    Key? key,
    required this.node,
    this.isSelected = false,
    this.onTap,
    required this.child,
  }) : super(key: key);

  Color _getStatusColor() {
    switch (node.status) {
      case NodeStatus.running:
        return AppColors.statusActive;
      case NodeStatus.attention:
        return AppColors.statusAlert;
      case NodeStatus.error:
        return AppColors.statusAlert;
      default:
        return AppColors.statusIdle;
    }
  }

  IconData _getNodeIcon() {
    switch (node.type) {
      case NodeType.terminal:
        return Icons.terminal_rounded;
      case NodeType.note:
        return Icons.edit_note_rounded;
      case NodeType.fileTree:
        return Icons.folder_copy_rounded;
      case NodeType.portal:
        return Icons.hub_rounded;
      case NodeType.routine:
        return Icons.schedule_rounded;
      default:
        return Icons.widgets_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: node.size.width,
        height: node.size.height,
        decoration: MacTheme.glassCardDecoration(
          isSelected: isSelected,
          borderRadius: 12.0,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra de título do Card estilo Mac
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.surfaceElevated,
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(_getNodeIcon(), size: 14, color: AppColors.textAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      node.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Indicador de status (pulso online)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getStatusColor(),
                      boxShadow: [
                        if (node.status == NodeStatus.running)
                          BoxShadow(
                            color: _getStatusColor().withOpacity(0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Conteúdo Interno do Card
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
