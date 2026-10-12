import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/canvas_node.dart';

/// Bloco de texto guardado pelo host: sem cartão, só o texto com o estilo do host.
class TextNodeWidget extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;

  const TextNodeWidget({super.key, required this.node, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final p = node.payload;
    final text = (p['text'] ?? '').toString();
    final fontSize = (p['fontSize'] as num?)?.toDouble() ?? 16;
    final weight = switch (p['fontWeight']) {
      'bold' => FontWeight.w700,
      'medium' => FontWeight.w500,
      _ => FontWeight.w400,
    };
    final color = parseHexColor(p['color'] as String?) ?? AppColors.textPrimary;
    final family = p['isMonospaced'] == true
        ? 'monospace'
        : (p['fontFamily'] == 'serif' ? 'serif' : null);

    return Container(
      width: node.size.width,
      height: node.size.height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: isSelected
            ? Border.all(color: AppColors.neonViolet.withValues(alpha: 0.7), width: 1)
            : null,
      ),
      child: Text(
        text.isEmpty ? node.title : text,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          fontFamily: family,
          height: 1.25,
        ),
      ),
    );
  }
}
