import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/workspace.dart';

/// Barra lateral (Sidebar) retrátil listando workspaces e andares estilo macOS Finder/Maestri
class WorkspaceSidebar extends StatelessWidget {
  final List<WorkspaceMeta> workspaces;
  final WorkspaceMeta? activeWorkspace;
  final Function(WorkspaceMeta) onSelectWorkspace;
  final VoidCallback onAddWorkspace;

  const WorkspaceSidebar({
    Key? key,
    required this.workspaces,
    this.activeWorkspace,
    required this.onSelectWorkspace,
    required this.onAddWorkspace,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabeçalho da Sidebar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Workspaces',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    onPressed: onAddWorkspace,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    color: AppColors.textSecondary,
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),

            // Lista de Workspaces
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                itemCount: workspaces.length,
                itemBuilder: (context, index) {
                  final ws = workspaces[index];
                  final isSelected = ws.id == activeWorkspace?.id;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.surfaceElevated
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? AppColors.borderHighlight : Colors.transparent,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(
                        ws.isPinned ? Icons.push_pin_rounded : Icons.space_dashboard_rounded,
                        size: 18,
                        color: isSelected ? AppColors.neonViolet : AppColors.textMuted,
                      ),
                      title: Text(
                        ws.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                      ),
                      trailing: ws.attentionCount > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.statusAlert.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${ws.attentionCount}',
                                style: const TextStyle(
                                  color: AppColors.statusAlert,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : (ws.runningTerminalCount > 0
                              ? Text(
                                  '${ws.runningTerminalCount}',
                                  style: const TextStyle(
                                    color: AppColors.statusActive,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                )
                              : null),
                      onTap: () {
                        onSelectWorkspace(ws);
                        Navigator.of(context).pop(); // fecha a drawer
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
