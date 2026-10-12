import 'package:flutter/material.dart';
import '../../core/network/api_terminals.dart';
import '../../models/agent_preset.dart';
import '../../models/agent_role.dart' show AgentRole;
import '../../models/floor.dart' show FloorMeta;
import '../../models/terminal_appearance.dart';

/// Abre o sheet "Novo terminal": preset, nome, comando, ícone, cor,
/// monitorActivity, Maestro, responsabilidade e andar.
///
/// [presets] vem de `listPresets()` (ou `getPresetCatalog().presets`).
/// [roles] vem de `RolesApi.listRoles()` (`GET /api/roles`).
/// [floors] são os andares do workspace; o térreo é sempre a primeira opção.
///
/// Ao confirmar, chama [onSubmit] com um [TerminalDraft] e fecha o sheet, e o
/// chamador faz `createTerminalFromDraft`. [onCreate] é a forma antiga
/// (preset, nome, Maestro), mantida para quem ainda não migrou; use uma ou outra.
Future<void> showCreateTerminalSheet(
  BuildContext context, {
  required List<AgentPreset> presets,
  List<AgentRole> roles = const [],
  List<FloorMeta> floors = const [],
  void Function(TerminalDraft draft)? onSubmit,
  @Deprecated('Use onSubmit (TerminalDraft).')
  void Function(String presetId, String name, bool maestroMode)? onCreate,
}) {
  assert(onSubmit != null || onCreate != null, 'Informe onSubmit.');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CreateTerminalSheet(
      presets: presets,
      roles: roles,
      floors: floors.where((f) => !f.isGround).toList(),
      onSubmit: onSubmit,
      onCreate: onCreate,
    ),
  );
}

class _CreateTerminalSheet extends StatefulWidget {
  final List<AgentPreset> presets;
  final List<AgentRole> roles;
  final List<FloorMeta> floors;
  final void Function(TerminalDraft draft)? onSubmit;
  final void Function(String presetId, String name, bool maestroMode)? onCreate;

  const _CreateTerminalSheet({
    required this.presets,
    required this.roles,
    required this.floors,
    this.onSubmit,
    this.onCreate,
  });

  @override
  State<_CreateTerminalSheet> createState() => _CreateTerminalSheetState();
}

class _CreateTerminalSheetState extends State<_CreateTerminalSheet> {
  String? _selectedId;
  bool _maestroMode = false;
  bool _monitorActivity = false;
  String? _roleId;
  String? _floorId;
  final _nameController = TextEditingController();
  final _commandController = TextEditingController();
  final _iconController = TextEditingController();
  final _colorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final preferred = widget.presets.where((p) => p.isDefault);
    final initial = preferred.isNotEmpty
        ? preferred.first
        : (widget.presets.isNotEmpty ? widget.presets.first : null);
    if (initial != null) _selectPreset(initial.id);
    _colorController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _iconController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  AgentPreset? get _selected {
    for (final p in widget.presets) {
      if (p.id == _selectedId) return p;
    }
    return null;
  }

  /// Escolher um preset preenche o comando com o do preset; o usuário pode trocar.
  void _selectPreset(String id) {
    _selectedId = id;
    final p = _selected;
    _commandController.text = p?.command ?? '';
  }

  String? get _colorError {
    final c = _colorController.text.trim();
    if (c.isEmpty || isHexColor(c)) return null;
    return 'Use a cor no formato #RRGGBB';
  }

  /// Monta o rascunho. Comando só vai se difere do preset; ícone e cor só se
  /// preenchidos, para o preset continuar valendo no resto.
  TerminalDraft? _buildDraft() {
    final preset = _selected;
    final command = _commandController.text.trim();
    final presetCommand = preset?.command ?? '';
    if (preset == null && command.isEmpty) return null;
    if (_colorError != null) return null;
    final name = _nameController.text.trim();
    return TerminalDraft(
      presetId: preset?.id,
      floorId: _floorId,
      name: name.isEmpty ? preset?.name : name,
      command: command == presetCommand ? null : command,
      icon: _iconController.text.trim(),
      color: _colorController.text.trim(),
      monitorActivity: _monitorActivity,
      maestroMode: _maestroMode,
      roleId: _roleId,
    );
  }

  bool get _canSubmit => _buildDraft() != null;

  void _submit() {
    final draft = _buildDraft();
    if (draft == null) return;
    Navigator.of(context).pop();
    final onSubmit = widget.onSubmit;
    if (onSubmit != null) {
      onSubmit(draft);
    } else {
      widget.onCreate!(draft.presetId ?? '', draft.name ?? '', _maestroMode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final preset = _selected;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Novo terminal', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (widget.presets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Nenhum preset disponível no host.'),
                )
              else ...[
                for (final p in widget.presets)
                  ListTile(
                    key: ValueKey('preset-${p.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.terminal),
                    title: Text(p.name),
                    subtitle: p.command == null ? null : Text(p.command!),
                    trailing: p.id == _selectedId ? const Icon(Icons.check) : null,
                    selected: p.id == _selectedId,
                    onTap: () => setState(() => _selectPreset(p.id)),
                  ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nome',
                  hintText: preset?.name ?? '',
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commandController,
                decoration: const InputDecoration(
                  labelText: 'Comando',
                  hintText: 'Vazio roda só o shell',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _iconController,
                      decoration: InputDecoration(
                        labelText: 'Ícone',
                        hintText: preset?.icon ?? '',
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _colorController,
                      decoration: InputDecoration(
                        labelText: 'Cor',
                        hintText: preset?.color ?? '#RRGGBB',
                        errorText: _colorError,
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey('role-$_roleId'),
                initialValue: _roleId,
                decoration: const InputDecoration(
                  labelText: 'Responsabilidade',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Nenhuma')),
                  for (final r in widget.roles)
                    DropdownMenuItem<String?>(value: r.id, child: Text(r.name)),
                ],
                onChanged: (v) => setState(() => _roleId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey('floor-$_floorId'),
                initialValue: _floorId,
                decoration: const InputDecoration(
                  labelText: 'Andar',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Térreo')),
                  for (final f in widget.floors)
                    DropdownMenuItem<String?>(value: f.id, child: Text(f.name)),
                ],
                onChanged: (v) => setState(() => _floorId = v),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Monitorar atividade'),
                value: _monitorActivity,
                onChanged: (v) => setState(() => _monitorActivity = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Modo Maestro'),
                subtitle: const Text('Dá ao agente o CLI maestri para criar outros terminais'),
                value: _maestroMode,
                onChanged: (v) => setState(() => _maestroMode = v),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _canSubmit ? _submit : null,
                child: const Text('Criar terminal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
