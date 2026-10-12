import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/canvas_node.dart';

/// Plaquinha que representa um terminal de outro andar ou workspace. Usa a cor e o ícone
/// do workspace remoto quando o host envia; seguir a plaquinha é abrir aquele andar.
class ConnectorNodeWidget extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;

  const ConnectorNodeWidget({super.key, required this.node, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(node.rawData['color'] as String?) ?? AppColors.neonViolet;
    final isRemoteWorkspace = node.payload['remoteWorkspaceId'] != null;
    final subtitle = node.rawData['subtitle'] as String?;
    return Container(
      width: node.size.width,
      height: node.size.height,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppColors.neonViolet : color.withValues(alpha: 0.7),
          width: isSelected ? 1.8 : 1.2,
        ),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Icon(isRemoteWorkspace ? Icons.workspaces_rounded : Icons.cable_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
