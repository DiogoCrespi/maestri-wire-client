import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/sidebar_layout.dart';
import '../../models/workspace.dart';

/// Barra lateral (Drawer) de workspaces, com pastas e grupos do layout do host.
///
/// Sem `layout` (ou com layout vazio) é a lista plana de antes. Com `layout`,
/// os workspaces aparecem sem pasta primeiro, depois as pastas de nível superior
/// e por fim os grupos (com as pastas de cada grupo). Ligação workspace → pasta
/// é pelo nome do resumo (`folderName`/`groupName`).
///
/// Toque longo num workspace chama `onWorkspaceLongPress` (ações: fixar,
/// renomear, editar, acordar, descarregar, limpar atenção, excluir).
class WorkspaceSidebar extends StatelessWidget {
  final List<WorkspaceMeta> workspaces;
  final WorkspaceMeta? activeWorkspace;
  final Function(WorkspaceMeta) onSelectWorkspace;
  final VoidCallback onAddWorkspace;
  final VoidCallback? onOpenRoutines;
  final VoidCallback? onOpenRoles;

  /// Pastas e grupos (de `WireController.sidebarLayout`). Null = lista plana.
  final SidebarLayout? layout;

  /// Ações de um workspace (toque longo). Null desliga o toque longo.
  final ValueChanged<WorkspaceMeta>? onWorkspaceLongPress;

  const WorkspaceSidebar({
    Key? key,
    required this.workspaces,
    this.activeWorkspace,
    required this.onSelectWorkspace,
    required this.onAddWorkspace,
    this.onOpenRoutines,
    this.onOpenRoles,
    this.layout,
    this.onWorkspaceLongPress,
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

            // Lista de Workspaces (plana ou em pastas e grupos)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                children: _buildEntries(context),
              ),
            ),

            // Ferramentas do host: rotinas e papéis de agente
            if (onOpenRoutines != null || onOpenRoles != null) ...[
              const Divider(height: 1, color: AppColors.border),
              if (onOpenRoutines != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.schedule_rounded, size: 18),
                  title: const Text('Rotinas', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenRoutines!();
                  },
                ),
              if (onOpenRoles != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.badge_outlined, size: 18),
                  title: const Text('Papéis de agente', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenRoles!();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  /// Monta as linhas da lista. Workspace cujo folder/grupo não existe no layout
  /// aparece sem pasta (nunca some).
  List<Widget> _buildEntries(BuildContext context) {
    final lay = layout;
    if (lay == null || lay.isEmpty) {
      return [for (final ws in workspaces) _tile(context, ws)];
    }

    final folderNames = {
      for (final f in lay.folders) f.name,
      for (final g in lay.groups) ...g.folders.map((f) => f.name),
    };
    final groupNames = {for (final g in lay.groups) g.name};
    bool unplaced(WorkspaceMeta ws) =>
        (ws.folderName == null || !folderNames.contains(ws.folderName)) &&
        (ws.groupName == null || !groupNames.contains(ws.groupName));

    final widgets = <Widget>[
      for (final ws in workspaces)
        if (unplaced(ws)) _tile(context, ws),
    ];

    for (final folder in lay.folders) {
      final members = [
        for (final ws in workspaces)
          if (ws.folderName == folder.name && (ws.groupName == null || !groupNames.contains(ws.groupName)))
            ws,
      ];
      widgets.add(_section(context, folder.name, Icons.folder_outlined, members));
    }

    for (final group in lay.groups) {
      final groupChildren = <Widget>[
        for (final ws in workspaces)
          if (ws.groupName == group.name && (ws.folderName == null || !folderNames.contains(ws.folderName)))
            _tile(context, ws),
        for (final folder in group.folders)
          _section(
            context,
            folder.name,
            Icons.folder_outlined,
            [for (final ws in workspaces) if (ws.groupName == group.name && ws.folderName == folder.name) ws],
          ),
      ];
      widgets.add(_expansion(group.name, Icons.workspaces_outline, groupChildren));
    }
    return widgets;
  }

  Widget _section(BuildContext context, String name, IconData icon, List<WorkspaceMeta> members) {
    return _expansion(name, icon, [for (final ws in members) _tile(context, ws)]);
  }

  Widget _expansion(String name, IconData icon, List<Widget> children) {
    return ExpansionTile(
      dense: true,
      initiallyExpanded: true,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(icon, size: 18, color: AppColors.textMuted),
      title: Text(
        name,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: children.isEmpty
          ? const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Vazio', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            ]
          : children,
    );
  }

  Widget _tile(BuildContext context, WorkspaceMeta ws) {
    final isSelected = ws.id == activeWorkspace?.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.surfaceElevated : Colors.transparent,
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
                  color: AppColors.statusAlert.withValues(alpha: 0.2),
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
        onLongPress: onWorkspaceLongPress == null ? null : () => onWorkspaceLongPress!(ws),
      ),
    );
  }
}
