import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/network/api_floors.dart';
import '../../models/floor.dart';
import '../../models/floor_hooks.dart';
import '../../state/wire_controller.dart';

/// Folha de hooks de andar. Os hooks são do workspace (GET/PUT, substituídos
/// por inteiro); executar e parar valem para este andar. Só o host executa.
Future<void> showHooksSheet(
  BuildContext context,
  WireController controller,
  FloorMeta floor,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: HooksSheet(controller: controller, floor: floor),
      ),
    ),
  );
}

class HooksSheet extends StatefulWidget {
  final WireController controller;
  final FloorMeta floor;

  const HooksSheet({super.key, required this.controller, required this.floor});

  @override
  State<HooksSheet> createState() => _HooksSheetState();
}

class _HooksSheetState extends State<HooksSheet> {
  FloorHooksSnapshot? _snapshot;
  FloorHooks _hooks = FloorHooks.empty;
  String _saved = '';
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _info;

  bool get _dirty => jsonEncode(_hooks.toJson()) != _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Relê hooks e execuções do host. Edições não salvas são descartadas.
  Future<void> _load({bool keepEdits = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await widget.controller.getFloorHooks();
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        if (!keepEdits) _hooks = snap.hooks;
        _saved = jsonEncode(snap.hooks.toJson());
      });
    } catch (e) {
      if (mounted) setState(() => _error = hostErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
      if (mounted) setState(() => _info = success);
      await _load(keepEdits: true);
    } catch (e) {
      if (mounted) setState(() => _error = hostErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCommand(String section, HookCommand? existing) async {
    final ctrl = TextEditingController(text: existing?.command ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Novo comando' : 'Editar comando'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Comando de shell'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    final list = [..._hooks.section(section)];
    if (existing == null) {
      list.add(HookCommand(id: HookCommand.newId(), command: text));
    } else {
      final i = list.indexWhere((c) => c.id == existing.id);
      if (i >= 0) list[i] = existing.copyWith(command: text);
    }
    setState(() => _hooks = _hooks.withSection(section, list));
  }

  void _toggleCommand(String section, HookCommand cmd, bool enabled) {
    final list = [
      for (final c in _hooks.section(section))
        if (c.id == cmd.id) c.copyWith(isEnabled: enabled) else c,
    ];
    setState(() => _hooks = _hooks.withSection(section, list));
  }

  void _removeCommand(String section, HookCommand cmd) {
    final list = [for (final c in _hooks.section(section)) if (c.id != cmd.id) c];
    setState(() => _hooks = _hooks.withSection(section, list));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = _snapshot;
    final floor = widget.floor;
    // Execuções só valem com o que está salvo no host
    final canRun = !_busy && !_dirty && (_hooks.isEnabled);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Hooks de "${floor.name}"', style: theme.textTheme.titleMedium),
            ),
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _busy ? null : () => _load(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (_loading && snap == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hooks habilitados'),
            value: _hooks.isEnabled,
            onChanged: _busy ? null : (v) => setState(() => _hooks = _hooks.copyWith(isEnabled: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Executar setup automaticamente'),
            value: _hooks.autoRunSetup,
            onChanged: _busy ? null : (v) => setState(() => _hooks = _hooks.copyWith(autoRunSetup: v)),
          ),
          for (final section in hookSections)
            _SectionCard(
              label: hookSectionLabel(section),
              commands: _hooks.section(section),
              runFor: (id) => snap?.runFor(id),
              canRun: canRun,
              busy: _busy,
              onAdd: () => _editCommand(section, null),
              onEdit: (cmd) => _editCommand(section, cmd),
              onToggle: (cmd, v) => _toggleCommand(section, cmd, v),
              onRemove: (cmd) => _removeCommand(section, cmd),
              onRun: (cmd) => _act(
                () => widget.controller.floorHookAction(floor, action: 'run', commandId: cmd.id),
                success: 'Comando iniciado.',
              ),
              onStop: (cmd) => _act(
                () => widget.controller.floorHookAction(floor, action: 'stop', commandId: cmd.id),
                success: 'Parada pedida.',
              ),
              onRunSection: _hooks.section(section).isEmpty
                  ? null
                  : () => _act(
                        () => widget.controller.floorHookAction(
                          floor,
                          action: 'runSection',
                          section: section,
                        ),
                        success: 'Seção iniciada.',
                      ),
            ),
          const SizedBox(height: 8),
          Text(
            'Salvar substitui os hooks inteiros do workspace. Executar usa o que está salvo.',
            style: theme.textTheme.bodySmall,
          ),
          if (_dirty)
            Text('Há alterações não salvas: salve antes de executar.',
                style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy || !_dirty
                ? null
                : () => _act(
                      () => widget.controller.saveFloorHooks(_hooks),
                      success: 'Hooks salvos.',
                    ),
            child: const Text('Salvar hooks'),
          ),
        ],
        if (_busy)
          const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        if (_info != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_info!, style: theme.textTheme.bodySmall),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String label;
  final List<HookCommand> commands;
  final HookRun? Function(String commandId) runFor;
  final bool canRun;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<HookCommand> onEdit;
  final void Function(HookCommand, bool) onToggle;
  final ValueChanged<HookCommand> onRemove;
  final ValueChanged<HookCommand> onRun;
  final ValueChanged<HookCommand> onStop;
  final VoidCallback? onRunSection;

  const _SectionCard({
    required this.label,
    required this.commands,
    required this.runFor,
    required this.canRun,
    required this.busy,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
    required this.onRemove,
    required this.onRun,
    required this.onStop,
    required this.onRunSection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
                IconButton(
                  tooltip: 'Executar seção',
                  onPressed: canRun && onRunSection != null ? onRunSection : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
                IconButton(
                  tooltip: 'Adicionar comando',
                  onPressed: busy ? null : onAdd,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (commands.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 0, bottom: 8),
                child: Text('Nenhum comando.', style: theme.textTheme.bodySmall),
              ),
            for (final cmd in commands) _commandRow(context, theme, cmd),
          ],
        ),
      ),
    );
  }

  Widget _commandRow(BuildContext context, ThemeData theme, HookCommand cmd) {
    final run = runFor(cmd.id);
    final running = run?.isRunning ?? false;
    final status = running
        ? 'executando'
        : run?.exitCode != null
            ? 'saiu com ${run!.exitCode}'
            : null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: InkWell(
        onTap: busy ? null : () => onEdit(cmd),
        child: Text(
          cmd.command,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'monospace',
            color: cmd.isEnabled ? null : theme.disabledColor,
          ),
        ),
      ),
      subtitle: status == null ? null : Text(status, style: theme.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: cmd.isEnabled,
            onChanged: busy ? null : (v) => onToggle(cmd, v),
          ),
          if (running)
            IconButton(
              tooltip: 'Parar',
              onPressed: busy ? null : () => onStop(cmd),
              icon: const Icon(Icons.stop_rounded),
            )
          else
            IconButton(
              tooltip: 'Executar',
              onPressed: canRun && cmd.isEnabled ? () => onRun(cmd) : null,
              icon: const Icon(Icons.play_circle_outline_rounded),
            ),
          IconButton(
            tooltip: 'Remover',
            onPressed: busy ? null : () => onRemove(cmd),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}
