import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/workspace.dart';

/// Barra de navegação superior com estética macOS (Traffic lights, status e seletor)
class MacWindowBar extends StatelessWidget {
  final String? hostName;
  final bool isConnected;
  final WorkspaceMeta? activeWorkspace;
  final VoidCallback onOpenSidebar;
  final VoidCallback onNewPrompt;

  const MacWindowBar({
    Key? key,
    this.hostName,
    this.isConnected = false,
    this.activeWorkspace,
    required this.onOpenSidebar,
    required this.onNewPrompt,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 550;
          return Row(
            children: [
              // Botões de Semáforo Mac (Traffic Lights) - apenas em telas largas
              if (!isCompact) ...[
                Row(
                  children: [
                    _trafficDot(const Color(0xFFFF5F56)), // Fechar
                    const SizedBox(width: 7),
                    _trafficDot(const Color(0xFFFFBD2E)), // Minimizar
                    const SizedBox(width: 7),
                    _trafficDot(const Color(0xFF27C93F)), // Expandir
                  ],
                ),
                const SizedBox(width: 12),
              ],

              // Botão de abrir barra lateral / workspaces
              IconButton(
                onPressed: onOpenSidebar,
                icon: const Icon(Icons.menu_rounded, size: 20),
                color: AppColors.textSecondary,
                tooltip: 'Workspaces',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 6),

              // Título do Workspace Ativo
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        activeWorkspace?.name ?? 'Maestri Canvas',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if ((activeWorkspace?.runningTerminalCount ?? 0) > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.statusActive.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.statusActive.withOpacity(0.3)),
                        ),
                        child: Text(
                          isCompact
                              ? '${activeWorkspace?.runningTerminalCount ?? 0}'
                              : '${activeWorkspace?.runningTerminalCount ?? 0} ativos',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.statusActive,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Indicador de Conexão com o Servidor Linux
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected
                            ? AppColors.statusActive
                            : AppColors.statusAlert,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      hostName ?? 'Wire',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Botão de Enviar Prompt / Ação Rápida
              isCompact
                  ? Container(
                      decoration: BoxDecoration(
                        color: AppColors.neonViolet,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: IconButton(
                        onPressed: onNewPrompt,
                        icon: const Icon(Icons.bolt_rounded, size: 18, color: Colors.white),
                        tooltip: 'Novo Prompt',
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: onNewPrompt,
                      icon: const Icon(Icons.bolt_rounded, size: 15),
                      label: const Text('Prompt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.neonViolet,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 0,
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }

  Widget _trafficDot(Color color) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
