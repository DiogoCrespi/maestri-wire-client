import 'package:flutter/material.dart';
import '../../core/network/api_floors.dart';
import '../../models/floor.dart';
import '../../state/wire_controller.dart';
import 'floor_status_editor.dart';
import 'hooks_sheet.dart';
import 'landing_sheet.dart';
import 'pull_request_sheet.dart';

/// Fluxos de andar disparados pelo seletor: criar, e gerenciar um andar existente.
/// Ações destrutivas (descarregar, excluir) pedem confirmação antes.

/// O campo do diálogo ainda está na árvore durante a animação de saída:
/// o controlador só pode ser descartado depois do próximo frame.
void _disposeAfterFrame(TextEditingController c) {
  WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
}

String _errorText(Object e) => hostErrorText(e);

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> createFloorFlow(BuildContext context, WireController c) async {
  final nameCtrl = TextEditingController();
  var isolate = false;
  final result = await showDialog<({String name, bool isolate})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Novo andar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nome do andar'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Isolar com git (worktree)'),
              subtitle: const Text('Exige um repositório git no workspace'),
              value: isolate,
              onChanged: (v) => setLocal(() => isolate = v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx, (name: name, isolate: isolate));
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    ),
  );
  _disposeAfterFrame(nameCtrl);
  if (result == null || !context.mounted) return;
  try {
    await c.createFloor(result.name, gitIsolation: result.isolate);
    if (context.mounted) _snack(context, 'Andar "${result.name}" criado.');
  } catch (e) {
    if (context.mounted) _snack(context, 'Não foi possível criar o andar: ${_errorText(e)}');
  }
}

Future<void> manageFloorFlow(BuildContext context, WireController c, FloorMeta floor) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: Text(floor.name),
            subtitle: Text(floor.branch == null ? 'Gerenciar andar' : 'Gerenciar andar · ${floor.branch}'),
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Definir status'),
            subtitle: const Text('Estado, relato e progresso'),
            onTap: () => Navigator.pop(ctx, 'status'),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline_rounded),
            title: const Text('Renomear'),
            onTap: () => Navigator.pop(ctx, 'rename'),
          ),
          if (!floor.isGround)
            ListTile(
              leading: const Icon(Icons.call_split_rounded),
              title: const Text('Pull request'),
              subtitle: const Text('Contexto, abrir, verificar, merge, remover'),
              onTap: () => Navigator.pop(ctx, 'pr'),
            ),
          ListTile(
            leading: const Icon(Icons.terminal_rounded),
            title: const Text('Hooks'),
            subtitle: const Text('Setup, run e teardown deste andar'),
            onTap: () => Navigator.pop(ctx, 'hooks'),
          ),
          ListTile(
            leading: const Icon(Icons.power_settings_new_rounded),
            title: const Text('Descarregar (para os terminais)'),
            onTap: () => Navigator.pop(ctx, 'unload'),
          ),
          if (!floor.isGround)
            ListTile(
              leading: const Icon(Icons.merge_rounded),
              title: const Text('Aterrissar (trazer para o projeto)'),
              subtitle: const Text('Prévia com branches, arquivos e conflitos'),
              onTap: () => Navigator.pop(ctx, 'land'),
            ),
          if (!floor.isGround)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Excluir andar', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'status':
      await showFloorStatusEditor(context, c, floor);
    case 'rename':
      await _renameFlow(context, c, floor);
    case 'pr':
      await showPullRequestSheet(context, c, floor);
    case 'hooks':
      await showHooksSheet(context, c, floor);
    case 'unload':
      await _confirmThen(
        context,
        title: 'Descarregar andar?',
        body: 'Os terminais deste andar serão parados e voltam quando você visitar o andar de novo.',
        action: () => c.unloadFloor(floor),
        success: 'Andar descarregado.',
      );
    case 'land':
      await showLandingSheet(context, c, floor);
    case 'delete':
      await _confirmThen(
        context,
        title: 'Excluir andar?',
        body: 'O andar "${floor.name}" será removido do host. Esta ação não pode ser desfeita.',
        action: () => c.deleteFloor(floor),
        success: 'Andar excluído.',
        destructive: true,
      );
  }
}

Future<void> _renameFlow(BuildContext context, WireController c, FloorMeta floor) async {
  final ctrl = TextEditingController(text: floor.name);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Renomear andar'),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  _disposeAfterFrame(ctrl);
  if (name == null || name.isEmpty || !context.mounted) return;
  try {
    await c.renameFloor(floor, name);
    if (context.mounted) _snack(context, 'Andar renomeado.');
  } catch (e) {
    if (context.mounted) _snack(context, 'Não foi possível renomear: ${_errorText(e)}');
  }
}

Future<void> _confirmThen(
  BuildContext context, {
  required String title,
  required String body,
  required Future<void> Function() action,
  required String success,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Colors.redAccent)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await action();
    if (context.mounted) _snack(context, success);
  } catch (e) {
    if (context.mounted) _snack(context, _errorText(e));
  }
}
