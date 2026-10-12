import 'package:flutter/material.dart';
import '../../core/network/api_floors.dart';
import '../../core/network/api_workspaces.dart';
import '../../models/sidebar_layout.dart';
import '../../models/workspace.dart';
import '../../state/wire_controller.dart';

/// Fluxos de workspace: criar, editar (nome, pasta, lugar na barra lateral) e
/// as ações da barra (fixar, renomear, acordar, descarregar, limpar atenção,
/// excluir). Excluir pede que a pessoa digite o nome do workspace.

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
}

/// Opções de lugar (pasta, senão grupo, senão nível superior), a partir do layout.
class PlacementOption {
  final String key;
  final String label;
  final WorkspacePlacement placement;

  const PlacementOption(this.key, this.label, this.placement);
}

List<PlacementOption> placementOptions(SidebarLayout layout) => [
      const PlacementOption('top', 'Nível superior', WorkspacePlacement.topLevel),
      for (final f in layout.folders)
        PlacementOption('folder:${f.id}', 'Pasta: ${f.name}', WorkspacePlacement(folderId: f.id)),
      for (final g in layout.groups) ...[
        PlacementOption('group:${g.id}', 'Grupo: ${g.name}', WorkspacePlacement(groupId: g.id)),
        for (final f in g.folders)
          PlacementOption(
            'folder:${f.id}',
            'Grupo ${g.name} / ${f.name}',
            WorkspacePlacement(folderId: f.id),
          ),
      ],
    ];

/// Chave do lugar atual de um workspace, pelo nome da pasta/grupo do resumo.
String currentPlacementKey(WorkspaceMeta ws, SidebarLayout layout) {
  if (ws.folderName != null) {
    for (final g in layout.groups) {
      if (ws.groupName == g.name) {
        for (final f in g.folders) {
          if (f.name == ws.folderName) return 'folder:${f.id}';
        }
      }
    }
    for (final f in layout.folders) {
      if (f.name == ws.folderName) return 'folder:${f.id}';
    }
  }
  if (ws.groupName != null) {
    for (final g in layout.groups) {
      if (g.name == ws.groupName) return 'group:${g.id}';
    }
  }
  return 'top';
}

/// Novo Workspace: nome, diretório de trabalho (no host), pasta e lugar.
/// Se o diretório não existe (404), oferece criá-lo (`createDirectory`).
Future<void> createWorkspaceFlow(BuildContext context, WireController controller) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _WorkspaceDialog(controller: controller),
  );
  if (ok == true && context.mounted) _snack(context, 'Workspace criado.');
}

/// Editar Workspace: só envia os campos que mudaram.
Future<void> editWorkspaceSheet(
  BuildContext context,
  WireController controller,
  WorkspaceMeta ws,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _WorkspaceDialog(controller: controller, existing: ws),
  );
  if (ok == true && context.mounted) _snack(context, 'Workspace atualizado.');
}

/// Ações de um workspace na barra lateral (toque longo).
Future<void> showWorkspaceActions(
  BuildContext context,
  WireController controller,
  WorkspaceMeta ws,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.space_dashboard_rounded),
            title: Text(ws.name),
            subtitle: Text(ws.workingDirectory ?? 'Workspace'),
          ),
          ListTile(
            leading: Icon(ws.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            title: Text(ws.isPinned ? 'Desafixar' : 'Fixar'),
            onTap: () => Navigator.pop(ctx, 'pin'),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline_rounded),
            title: const Text('Renomear'),
            onTap: () => Navigator.pop(ctx, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar workspace'),
            subtitle: const Text('Diretório e lugar na barra lateral'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Acordar'),
            subtitle: const Text('Inicia os terminais sem ativar o workspace no host'),
            onTap: () => Navigator.pop(ctx, 'wake'),
          ),
          ListTile(
            leading: const Icon(Icons.power_settings_new_rounded),
            title: const Text('Descarregar workspace'),
            subtitle: const Text('Para todos os terminais do workspace'),
            onTap: () => Navigator.pop(ctx, 'unload'),
          ),
          if (ws.attentionCount > 0)
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('Limpar atenção'),
              onTap: () => Navigator.pop(ctx, 'attention'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: const Text('Excluir workspace', style: TextStyle(color: Colors.redAccent)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  try {
    switch (action) {
      case 'pin':
        await controller.pinWorkspace(ws, pinned: !ws.isPinned);
      case 'rename':
        final name = await _askText(context, 'Renomear workspace', ws.name);
        if (name == null || name.isEmpty || !context.mounted) return;
        await controller.renameWorkspace(ws, name);
      case 'edit':
        await editWorkspaceSheet(context, controller, ws);
      case 'wake':
        await controller.wakeWorkspace(ws);
        if (context.mounted) _snack(context, 'Terminais acordados.');
      case 'unload':
        final ok = await _confirm(
          context,
          'Descarregar workspace?',
          'Todos os terminais de "${ws.name}" serão parados.',
        );
        if (!ok || !context.mounted) return;
        await controller.unloadWorkspace(ws);
        if (context.mounted) _snack(context, 'Workspace descarregado.');
      case 'attention':
        await controller.clearWorkspaceAttention(ws);
      case 'delete':
        final typed = await _confirmDelete(context, ws);
        if (!typed || !context.mounted) return;
        await controller.deleteWorkspace(ws);
        if (context.mounted) _snack(context, 'Workspace excluído.');
    }
  } catch (e) {
    if (context.mounted) _snack(context, hostErrorText(e));
  }
}

Future<String?> _askText(BuildContext context, String title, String initial) async {
  final ctrl = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Salvar')),
      ],
    ),
  );
  ctrl.dispose();
  return value;
}

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
      ],
    ),
  );
  return ok == true;
}

Future<bool> _confirmDelete(BuildContext context, WorkspaceMeta ws) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Excluir workspace?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Esta ação não pode ser desfeita. Digite "${ws.name}" para confirmar.'),
            TextField(controller: ctrl, onChanged: (_) => setLocal(() {})),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: ctrl.text.trim() == ws.name
                ? () => Navigator.pop(ctx, true)
                : null,
            child: const Text('Excluir'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return ok == true;
}

class _WorkspaceDialog extends StatefulWidget {
  final WireController controller;
  final WorkspaceMeta? existing;

  const _WorkspaceDialog({required this.controller, this.existing});

  @override
  State<_WorkspaceDialog> createState() => _WorkspaceDialogState();
}

class _WorkspaceDialogState extends State<_WorkspaceDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _dir =
      TextEditingController(text: widget.existing?.workingDirectory ?? '');
  late final String _initialDir = widget.existing?.workingDirectory ?? '';
  bool _createDir = false;
  late String _placementKey = widget.existing == null
      ? 'top'
      : currentPlacementKey(widget.existing!, widget.controller.sidebarLayout);
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _dir.dispose();
    super.dispose();
  }

  WorkspacePlacement get _placement {
    for (final o in placementOptions(widget.controller.sidebarLayout)) {
      if (o.key == _placementKey) return o.placement;
    }
    return WorkspacePlacement.topLevel;
  }

  Future<void> _browse() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _DirectoryBrowser(
        controller: widget.controller,
        start: _dir.text.trim(),
      ),
    );
    if (picked != null && mounted) setState(() => _dir.text = picked);
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Informe um nome.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        final dir = _dir.text.trim();
        final dirChanged = dir != _initialDir.trim();
        final placementChanged = _placementKey !=
            currentPlacementKey(widget.existing!, widget.controller.sidebarLayout);
        await widget.controller.updateWorkspace(
          widget.existing!,
          name: name == widget.existing!.name ? null : name,
          workingDirectory: dirChanged ? dir : null,
          createDirectory: dirChanged && _createDir,
          placement: placementChanged ? _placement : null,
        );
      } else {
        await _createWithRetry(name);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = hostErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 404 com diretório informado = o diretório não existe: oferece criá-lo.
  Future<void> _createWithRetry(String name) async {
    final dir = _dir.text.trim();
    try {
      await widget.controller.createWorkspace(
        name: name,
        workingDirectory: dir.isEmpty ? null : dir,
        createDirectory: _createDir,
        placement: _placement,
      );
    } on FloorApiException catch (e) {
      if (e.statusCode != 404 || dir.isEmpty || _createDir || !mounted) rethrow;
      final create = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Criar a pasta?'),
          content: Text('O diretório "$dir" não existe no host. Criar?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar')),
          ],
        ),
      );
      if (create != true) rethrow;
      setState(() => _createDir = true);
      await widget.controller.createWorkspace(
        name: name,
        workingDirectory: dir,
        createDirectory: true,
        placement: _placement,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = placementOptions(widget.controller.sidebarLayout);
    final keys = options.map((o) => o.key).toSet();
    final value = keys.contains(_placementKey) ? _placementKey : 'top';

    return AlertDialog(
      title: Text(_isEdit ? 'Editar workspace' : 'Novo workspace'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              enabled: !_busy,
              autofocus: !_isEdit,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dir,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Diretório no host',
                      hintText: '~/projetos/app',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Escolher pasta',
                  onPressed: _busy ? null : _browse,
                  icon: const Icon(Icons.folder_open_rounded),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Criar o diretório se não existir'),
              value: _createDir,
              onChanged: _busy ? null : (v) => setState(() => _createDir = v),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: value,
              decoration: const InputDecoration(labelText: 'Lugar na barra lateral'),
              items: [
                for (final o in options) DropdownMenuItem(value: o.key, child: Text(o.label)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _placementKey = v ?? 'top'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_isEdit ? 'Salvar' : 'Criar'),
        ),
      ],
    );
  }
}

/// Navega as pastas do disco do host (GET /api/directories?path=).
/// Retorna o caminho escolhido, ou null.
class _DirectoryBrowser extends StatefulWidget {
  final WireController controller;
  final String start;

  const _DirectoryBrowser({required this.controller, required this.start});

  @override
  State<_DirectoryBrowser> createState() => _DirectoryBrowserState();
}

class _DirectoryBrowserState extends State<_DirectoryBrowser> {
  DirectoryListing? _listing;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _open(widget.start);
  }

  Future<void> _open(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await widget.controller.client.listDirectories(path: path);
      if (mounted) setState(() => _listing = listing);
    } catch (e) {
      if (mounted) setState(() => _error = hostErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _parent(String path) {
    final trimmed = path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
    final i = trimmed.lastIndexOf('/');
    if (i <= 0) return i == 0 ? '/' : '';
    return trimmed.substring(0, i);
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    return AlertDialog(
      title: const Text('Escolher pasta'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            Text(listing?.path.isEmpty ?? true ? 'Pasta pessoal' : listing!.path,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Expanded(
              child: listing == null
                  ? const SizedBox.shrink()
                  : ListView(
                      children: [
                        if (listing.path.isNotEmpty)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.arrow_upward_rounded),
                            title: const Text('..'),
                            onTap: () => _open(_parent(listing.path)),
                          ),
                        for (final d in listing.directories)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(d.name),
                            onTap: () => _open(d.path),
                          ),
                        if (listing.isTruncated)
                          const ListTile(dense: true, title: Text('Lista truncada.')),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: listing == null ? null : () => Navigator.pop(context, listing.path),
          child: const Text('Usar esta pasta'),
        ),
      ],
    );
  }
}
