import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/canvas_node.dart';
import '../../core/network/wire_client.dart';
import 'node_card.dart';
import 'portal_live_preview.dart';

/// Widget de Nó de Portal Web (Navegador Integrado) do Maestri Wire
class PortalNodeWidget extends StatelessWidget {
  final CanvasNode node;
  final bool isSelected;
  final VoidCallback? onTap;
  final WireClient? client;

  const PortalNodeWidget({
    Key? key,
    required this.node,
    this.isSelected = false,
    this.onTap,
    this.client,
  }) : super(key: key);

  String? get _portalId {
    final portalData = node.rawData['portal'] as Map<String, dynamic>?;
    return portalData?['portalId'] as String?;
  }

  String get _url {
    final portalData = node.rawData['portal'] as Map<String, dynamic>?;
    return portalData?['currentURL'] ??
        portalData?['url'] ??
        node.rawData['subtitle'] ??
        'https://' + node.title;
  }

  @override
  Widget build(BuildContext context) {
    return NodeCard(
      node: node,
      isSelected: isSelected,
      onTap: onTap,
      child: Container(
        color: const Color(0xFF13151D),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra de Endereços estilo Safari/macOS
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: AppColors.surfaceElevated,
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, size: 12, color: AppColors.statusActive),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.background.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _url,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textPrimary,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textMuted),
                ],
              ),
            ),

            // Conteúdo do Portal: prévia ao vivo do host, ou o cartão de status
            Expanded(
              child: _portalId != null && client != null
                  ? PortalLivePreview(
                      client: client!,
                      portalId: _portalId!,
                      fallback: _statusCard(),
                    )
                  : _statusCard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.neonCobalt.withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.neonCobalt.withOpacity(0.4)),
                        ),
                        child: const Icon(
                          Icons.language_rounded,
                          size: 28,
                          color: AppColors.neonCobalt,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        node.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _url,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.statusActive.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.statusActive.withOpacity(0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 11, color: AppColors.statusActive),
                            SizedBox(width: 4),
                            Text(
                              'Portal Web Ativo no Linux',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.statusActive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
  }
}
