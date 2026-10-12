import 'package:flutter/material.dart';
import '../../core/network/api_roles.dart';
import '../../core/network/wire_client.dart';
import '../../models/agent_role.dart';

/// Tela de responsabilidades de agente do host: lista, criar, editar e remover.
///
/// Abra com `RolesScreen(client: client)` para gerenciar as responsabilidades.
/// Passe também `terminalId` e `terminalName` para ver e trocar a
/// responsabilidade daquele terminal no topo da tela.
class RolesScreen extends StatefulWidget {
  final WireClient client;
  final String? terminalId;
  final String? terminalName;

  const RolesScreen({
    super.key,
    required this.client,
    this.terminalId,
    this.terminalName,
  });

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  static final RegExp _hexColor = RegExp(r'^#[0-9A-Fa-f]{6}$');

  bool _loading = true;
  String? _loadError;
  List<AgentRole> _roles = const [];

  TerminalSettings? _terminal;
  String? _terminalRoleId;
  bool _savingTerminal = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  bool get _hasTerminal => widget.terminalId != null;

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final roles = await widget.client.listRoles();
      TerminalSettings? terminal;
      if (_hasTerminal) {
        terminal = await widget.client.getTerminalSettings(widget.terminalId!);
      }
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _terminal = terminal;
        _terminalRoleId = terminal?.roleId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = _describe(e);
        _loading = false;
      });
    }
  }

  String _describe(Object e) => e is RolesApiException ? e.message : e.toString();

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Color _parseColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16);
    if (clean.length != 6 || value == null) return Colors.grey;
    return Color(0xFF000000 | value);
  }

  // ---------- terminal ----------

  Future<void> _changeTerminalRole(String? newRoleId) async {
    final terminal = _terminal;
    if (terminal == null || widget.terminalId == null) return;
    final roleName = newRoleId == null
        ? 'Nenhuma'
        : _roles.firstWhere((r) => r.id == newRoleId, orElse: () => _roles.first).name;
    final ok = await _confirm(
      title: 'Trocar responsabilidade?',
      message:
          'O terminal${widget.terminalName != null ? ' "${widget.terminalName}"' : ''} passará a usar "$roleName". '
          'Se ele estiver em execução, será reiniciado.',
      confirmLabel: 'Trocar',
    );
    if (!ok || !mounted) return;

    setState(() => _savingTerminal = true);
    try {
      final updated = await widget.client.setTerminalRole(widget.terminalId!, newRoleId);
      if (!mounted) return;
      setState(() {
        _terminal = updated;
        _terminalRoleId = updated.roleId;
        _savingTerminal = false;
      });
      _snack('Responsabilidade do terminal atualizada.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _terminalRoleId = terminal.roleId;
        _savingTerminal = false;
      });
      _snack('Não foi possível trocar: ${_describe(e)}');
    }
  }

  Widget _terminalCard() {
    final terminal = _terminal;
    final knownIds = _roles.map((r) => r.id).toSet();
    final selected = (_terminalRoleId != null && knownIds.contains(_terminalRoleId))
        ? _terminalRoleId
        : null;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Responsabilidade do terminal${widget.terminalName != null ? ' "${widget.terminalName}"' : ''}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (terminal == null)
              const Text('Configurações indisponíveis.')
            else
              DropdownButtonFormField<String?>(
                // a chave força o rebuild quando a troca falha ou é cancelada
                key: ValueKey('terminal-role-$selected'),
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Nenhuma')),
                  for (final r in _roles)
                    DropdownMenuItem<String?>(value: r.id, child: Text(r.name)),
                ],
                onChanged: _savingTerminal ? null : _changeTerminalRole,
              ),
            const SizedBox(height: 8),
            const Text(
              'Trocar a responsabilidade reinicia o terminal se ele estiver em execução.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- criar / editar ----------

  Future<void> _openForm({AgentRole? existing}) async {
    final write = await showDialog<RoleWrite>(
      context: context,
      builder: (_) => _RoleFormDialog(existing: existing, isValidColor: _hexColor.hasMatch),
    );
    if (write == null || !mounted) return;

    if (existing != null) {
      final promptChanged = existing.prompt != write.prompt;
      if (promptChanged && existing.terminalsInUse > 0) {
        final ok = await _confirm(
          title: 'Alterar o prompt?',
          message:
              'Esta responsabilidade está em uso em ${existing.terminalsInUse} terminal(is). '
              'Os que estiverem em execução serão reiniciados com o novo prompt.',
          confirmLabel: 'Salvar',
        );
        if (!ok || !mounted) return;
      }
      await _run(() => widget.client.updateRole(existing.id, write), 'Responsabilidade atualizada.');
    } else {
      await _run(() => widget.client.createRole(write), 'Responsabilidade criada.');
    }
  }

  // ---------- remover ----------

  Future<void> _delete(AgentRole role) async {
    final inUse = role.terminalsInUse;
    final ok = await _confirm(
      title: 'Remover "${role.name}"?',
      message: inUse > 0
          ? 'Ela está em uso em $inUse terminal(is) e será removida deles. Essa ação não pode ser desfeita.'
          : 'Essa ação não pode ser desfeita.',
      confirmLabel: 'Remover',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() async => widget.client.deleteRole(role.id), 'Responsabilidade removida.');
  }

  Future<void> _run(Future<Object?> Function() action, String doneMessage) async {
    try {
      await action();
      _snack(doneMessage);
      await _reload();
    } catch (e) {
      _snack(_describe(e));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Responsabilidades'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _reload,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nova responsabilidade',
        onPressed: _loading ? null : () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _reload, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (_hasTerminal) _terminalCard(),
        if (_roles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Nenhuma responsabilidade. Toque em + para criar.')),
          ),
        for (final role in _roles) _roleTile(role),
      ],
    );
  }

  Widget _roleTile(AgentRole role) {
    final color = _parseColor(role.color);
    return ListTile(
      leading: CircleAvatar(backgroundColor: color, child: const Icon(Icons.smart_toy, color: Colors.white, size: 18)),
      title: Text(role.name),
      subtitle: Text(
        '${role.prompt}\n'
        '${role.terminalsInUse == 0 ? 'Não está em uso' : 'Em uso em ${role.terminalsInUse} terminal(is)'}'
        '${role.workspaceId != null ? ' · restrita a um workspace' : ''}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: () => _openForm(existing: role),
      trailing: IconButton(
        tooltip: 'Remover',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(role),
      ),
    );
  }
}

/// Formulário de criar/editar. Devolve o `RoleWrite` ou null ao cancelar.
class _RoleFormDialog extends StatefulWidget {
  final AgentRole? existing;
  final bool Function(String) isValidColor;

  const _RoleFormDialog({required this.existing, required this.isValidColor});

  @override
  State<_RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends State<_RoleFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late final TextEditingController _icon;
  late final TextEditingController _color;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _prompt = TextEditingController(text: e?.prompt ?? '');
    _icon = TextEditingController(text: e?.icon.isNotEmpty == true ? e!.icon : 'sparkles');
    _color = TextEditingController(text: e?.color.isNotEmpty == true ? e!.color : '#AF52DE');
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _icon.dispose();
    _color.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final prompt = _prompt.text.trim();
    final icon = _icon.text.trim().isEmpty ? 'sparkles' : _icon.text.trim();
    final color = _color.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Informe um nome.');
    if (prompt.isEmpty) return setState(() => _error = 'Informe o prompt.');
    if (!widget.isValidColor(color)) return setState(() => _error = 'Cor inválida. Use #RRGGBB.');
    Navigator.pop(
      context,
      RoleWrite(
        name: name,
        prompt: prompt,
        icon: icon,
        color: color,
        // PUT é substituição completa: mantém o escopo de workspace existente.
        workspaceId: widget.existing?.workspaceId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Editar responsabilidade' : 'Nova responsabilidade'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _prompt,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Prompt', alignLabelWithHint: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _icon,
                decoration: const InputDecoration(labelText: 'Ícone'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _color,
                decoration: const InputDecoration(labelText: 'Cor (#RRGGBB)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
