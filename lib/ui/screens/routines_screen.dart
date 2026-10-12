import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/network/api_routines.dart';
import '../../core/network/wire_client.dart';
import '../../models/routine.dart';
import '../../models/workspace.dart';

/// Tela de rotinas do host: lista, cria, edita, remove, executa e mostra o histórico.
///
/// Abrir: `Navigator.push(context, MaterialPageRoute(builder: (_) => RoutinesScreen(client: client, canWrite: isOwner)))`.
/// [canWrite] deve ser verdadeiro só para o papel owner; sem ele a tela é somente leitura.
class RoutinesScreen extends StatefulWidget {
  final WireClient client;
  final bool canWrite;

  const RoutinesScreen({super.key, required this.client, this.canWrite = true});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  RoutinesSnapshot? _snapshot;
  List<WorkspaceMeta> _workspaces = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await widget.client.listRoutines();
      List<WorkspaceMeta> workspaces = _workspaces;
      try {
        workspaces = await widget.client.getWorkspaces();
      } catch (_) {
        // a lista de workspaces só é necessária para criar lembretes
      }
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _workspaces = workspaces;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Roda uma escrita, mostra erros em SnackBar e recarrega a lista ao final.
  Future<void> _write(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) _snack(success);
    } catch (e) {
      _snack('Falha: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _targetName(String? terminalId) {
    if (terminalId == null) return 'Lembrete';
    final match = _snapshot?.targets.where((t) => t.id == terminalId);
    if (match == null || match.isEmpty) return 'Terminal desconhecido';
    final t = match.first;
    return t.floorName == null ? t.name : '${t.name} · ${t.floorName}';
  }

  Future<void> _openEditor([Routine? existing]) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final result = await Navigator.of(context).push<Routine>(
      MaterialPageRoute(
        builder: (_) => RoutineEditorScreen(
          existing: existing,
          targets: snapshot.targets,
          workspaces: _workspaces,
        ),
      ),
    );
    if (result == null) return;
    await _write(
      () => existing == null
          ? widget.client.createRoutine(result)
          : widget.client.updateRoutine(result),
      success: existing == null ? 'Rotina criada' : 'Rotina salva',
    );
  }

  Future<void> _confirmDelete(Routine routine) async {
    final ok = await _confirm(
      title: 'Remover rotina?',
      message: '"${routine.name}" será apagada do host. O histórico permanece.',
      action: 'Remover',
    );
    if (ok) {
      await _write(() => widget.client.deleteRoutine(routine.id),
          success: 'Rotina removida');
    }
  }

  Future<void> _confirmRun(Routine routine) async {
    final ok = await _confirm(
      title: 'Executar agora?',
      message: routine.isReminder
          ? 'Isto dispara o lembrete "${routine.name}" agora.'
          : 'Isto envia o prompt de "${routine.name}" ao terminal no host agora.',
      action: 'Executar',
    );
    if (ok) {
      await _write(
        () => widget.client.routineAction(routine.id, RoutineAction.run),
        success: 'Rotina disparada',
      );
    }
  }

  Future<void> _confirmClearHistory() async {
    final ok = await _confirm(
      title: 'Limpar histórico?',
      message:
          'Todas as execuções registradas serão apagadas. As rotinas ficam intactas.',
      action: 'Limpar',
    );
    if (ok) {
      await _write(() => widget.client.clearRoutineHistory(),
          success: 'Histórico limpo');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rotinas'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Rotinas'), Tab(text: 'Histórico')],
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading || _busy ? null : _load,
          ),
        ],
      ),
      floatingActionButton: widget.canWrite && _snapshot != null
          ? FloatingActionButton(
              tooltip: 'Nova rotina',
              onPressed: _busy ? null : () => _openEditor(),
              child: const Icon(Icons.add),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Não foi possível carregar as rotinas.\n$_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _load, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    final snapshot = _snapshot!;
    return Column(
      children: [
        if (!widget.canWrite)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(8),
            child: const Text(
                'Somente leitura: editar rotinas exige papel owner.',
                textAlign: TextAlign.center),
          ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildRoutineList(snapshot),
              _buildHistory(snapshot),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoutineList(RoutinesSnapshot snapshot) {
    if (snapshot.routines.isEmpty) {
      return const Center(child: Text('Nenhuma rotina no host.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        itemCount: snapshot.routines.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final r = snapshot.routines[i];
          return Card(
            child: ListTile(
              leading: Icon(
                  r.isReminder ? Icons.notifications_outlined : Icons.terminal),
              title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${r.schedule.describe()}\n${_targetName(r.terminalId)} · '
                '${r.fireCount} execuç${r.fireCount == 1 ? 'ão' : 'ões'}',
              ),
              isThreeLine: true,
              trailing: widget.canWrite
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: r.isEnabled,
                          onChanged: _busy
                              ? null
                              : (v) => _write(
                                    () => widget.client.routineAction(
                                      r.id,
                                      v
                                          ? RoutineAction.enable
                                          : RoutineAction.disable,
                                    ),
                                  ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            switch (v) {
                              case 'run':
                                _confirmRun(r);
                                break;
                              case 'edit':
                                _openEditor(r);
                                break;
                              case 'delete':
                                _confirmDelete(r);
                                break;
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'run', child: Text('Executar agora')),
                            PopupMenuItem(value: 'edit', child: Text('Editar')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Remover')),
                          ],
                        ),
                      ],
                    )
                  : Icon(r.isEnabled
                      ? Icons.check_circle_outline
                      : Icons.pause_circle_outline),
              onTap: widget.canWrite && !_busy ? () => _openEditor(r) : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistory(RoutinesSnapshot snapshot) {
    // O host envia do mais antigo ao mais novo; a lista mostra o mais recente primeiro.
    final history = snapshot.history.reversed.toList();
    return Column(
      children: [
        Expanded(
          child: history.isEmpty
              ? const Center(child: Text('Nenhuma execução registrada.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final h = history[i];
                      final local = h.firedAt.toLocal();
                      final when =
                          '${_two(local.day)}/${_two(local.month)} ${_two(local.hour)}:${_two(local.minute)}';
                      return ListTile(
                        dense: true,
                        title: Text(h.routineName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '$when · ${h.outcomeLabel}'
                          '${h.terminalName == null ? '' : ' · ${h.terminalName}'}',
                        ),
                      );
                    },
                  ),
                ),
        ),
        if (widget.canWrite && history.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _confirmClearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Limpar histórico'),
            ),
          ),
      ],
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Formulário de criar/editar uma rotina. Devolve o [Routine] via `Navigator.pop`.
class RoutineEditorScreen extends StatefulWidget {
  final Routine? existing;
  final List<RoutineTarget> targets;
  final List<WorkspaceMeta> workspaces;

  const RoutineEditorScreen({
    super.key,
    this.existing,
    required this.targets,
    required this.workspaces,
  });

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late final TextEditingController _preRun;
  late final TextEditingController _interval;
  late final TextEditingController _count;

  // Destino: terminal (targetId) ou lembrete (workspaceId sem terminal).
  bool _reminder = false;
  String? _targetId;
  String? _workspaceId;

  String _kind = 'daily';
  DateTime _onceAt = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  final Set<int> _weekdays = {2};

  String _endKind = 'never';
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));

  bool _skipIfBusy = false;
  bool _notifyOnFire = true;
  bool _isEnabled = true;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _name = TextEditingController(text: r?.name ?? '');
    _prompt = TextEditingController(text: r?.prompt ?? '');
    _preRun = TextEditingController(text: r?.preRunScript ?? '');
    _interval = TextEditingController(text: '${r?.schedule.seconds ?? 3600}');
    _count = TextEditingController(text: '${r?.endRepeat.count ?? 10}');
    if (r != null) {
      _reminder = r.isReminder;
      _targetId = r.terminalId;
      _workspaceId = r.workspaceId;
      _skipIfBusy = r.skipIfBusy;
      _notifyOnFire = r.notifyOnFire;
      _isEnabled = r.isEnabled;
      _kind = r.schedule.kind;
      if (r.schedule.at != null) _onceAt = r.schedule.at!.toLocal();
      if (r.schedule.hour != null) {
        _time =
            TimeOfDay(hour: r.schedule.hour!, minute: r.schedule.minute ?? 0);
      }
      if (r.schedule.weekdays.isNotEmpty) {
        _weekdays
          ..clear()
          ..addAll(r.schedule.weekdays);
      }
      _endKind = r.endRepeat.kind;
      if (r.endRepeat.date != null) _endDate = r.endRepeat.date!.toLocal();
    } else if (widget.targets.isNotEmpty) {
      _targetId = widget.targets.first.id;
      _workspaceId = widget.targets.first.workspaceId;
    } else if (widget.workspaces.isNotEmpty) {
      _workspaceId = widget.workspaces.first.id;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _preRun.dispose();
    _interval.dispose();
    _count.dispose();
    super.dispose();
  }

  RoutineSchedule _buildSchedule() {
    switch (_kind) {
      case 'once':
        return RoutineSchedule.once(_onceAt);
      case 'interval':
        return RoutineSchedule.interval(int.parse(_interval.text.trim()));
      case 'weekly':
        final days = _weekdays.toList()..sort();
        return RoutineSchedule.weekly(
            days: days, hourOfDay: _time.hour, minuteOfHour: _time.minute);
      default:
        return RoutineSchedule.daily(
            hourOfDay: _time.hour, minuteOfHour: _time.minute);
    }
  }

  RoutineEndRepeat _buildEnd() {
    switch (_endKind) {
      case 'afterCount':
        return RoutineEndRepeat.afterCount(int.parse(_count.text.trim()));
      case 'onDate':
        return RoutineEndRepeat.onDate(
            DateTime(_endDate.year, _endDate.month, _endDate.day));
      default:
        return const RoutineEndRepeat.never();
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_kind == 'weekly' && _weekdays.isEmpty) {
      _snack('Escolha ao menos um dia da semana.');
      return;
    }
    final workspaceId = _reminder ? _workspaceId : _workspaceIdForTarget();
    if (workspaceId == null) {
      _snack('Escolha um destino.');
      return;
    }
    final existing = widget.existing;
    final routine = Routine(
      id: existing?.id ?? _newId(),
      name: _name.text.trim(),
      workspaceId: workspaceId,
      terminalId: _reminder ? null : _targetId,
      prompt: _prompt.text.trim(),
      preRunScript: _preRun.text.trim().isEmpty ? null : _preRun.text.trim(),
      skipIfBusy: _skipIfBusy,
      schedule: _buildSchedule(),
      endRepeat: _buildEnd(),
      notifyOnFire: _notifyOnFire,
      isEnabled: _isEnabled,
      fireCount: existing?.fireCount ?? 0,
      lastFiredAt: existing?.lastFiredAt,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
    Navigator.of(context).pop(routine);
  }

  String? _workspaceIdForTarget() {
    for (final t in widget.targets) {
      if (t.id == _targetId) return t.workspaceId;
    }
    return _workspaceId;
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _pickOnceAt() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _onceAt,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_onceAt),
    );
    if (t == null) return;
    setState(
        () => _onceAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _pickEndDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _endDate = d);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Editar rotina' : 'Nova rotina'),
        actions: [TextButton(onPressed: _save, child: const Text('Salvar'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lembrete (sem terminal)'),
              subtitle: const Text('Só notifica; não roda nenhum comando.'),
              value: _reminder,
              onChanged: (v) => setState(() => _reminder = v),
            ),
            if (_reminder)
              DropdownButtonFormField<String>(
                value: widget.workspaces.any((w) => w.id == _workspaceId)
                    ? _workspaceId
                    : null,
                decoration: const InputDecoration(labelText: 'Workspace'),
                items: [
                  for (final w in widget.workspaces)
                    DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: (v) => setState(() => _workspaceId = v),
                validator: (v) => v == null ? 'Escolha um workspace' : null,
              )
            else
              DropdownButtonFormField<String>(
                value: widget.targets.any((t) => t.id == _targetId)
                    ? _targetId
                    : null,
                decoration: const InputDecoration(labelText: 'Terminal'),
                isExpanded: true,
                items: [
                  for (final t in widget.targets)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text(
                        t.floorName == null
                            ? t.name
                            : '${t.name} · ${t.floorName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _targetId = v),
                validator: (v) => v == null ? 'Escolha um terminal' : null,
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _prompt,
              decoration: InputDecoration(
                labelText: _reminder ? 'Notas do lembrete' : 'Prompt / comando',
              ),
              minLines: 2,
              maxLines: 6,
              validator: (v) {
                if (_reminder && (v == null || v.trim().isEmpty)) {
                  return 'Lembrete precisa de notas';
                }
                return null;
              },
            ),
            if (!_reminder) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _preRun,
                decoration: const InputDecoration(
                    labelText: 'Script antes de rodar (opcional)'),
                minLines: 1,
                maxLines: 4,
              ),
            ],
            const Divider(height: 32),
            DropdownButtonFormField<String>(
              value: _kind,
              decoration: const InputDecoration(labelText: 'Agendamento'),
              items: const [
                DropdownMenuItem(value: 'once', child: Text('Uma vez')),
                DropdownMenuItem(
                    value: 'interval', child: Text('A cada intervalo')),
                DropdownMenuItem(value: 'daily', child: Text('Todo dia')),
                DropdownMenuItem(
                    value: 'weekly', child: Text('Dias da semana')),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'daily'),
            ),
            const SizedBox(height: 12),
            ..._scheduleFields(),
            const Divider(height: 32),
            DropdownButtonFormField<String>(
              value: _endKind,
              decoration: const InputDecoration(labelText: 'Término'),
              items: const [
                DropdownMenuItem(value: 'never', child: Text('Nunca')),
                DropdownMenuItem(
                    value: 'afterCount', child: Text('Após N execuções')),
                DropdownMenuItem(value: 'onDate', child: Text('Numa data')),
              ],
              onChanged: (v) => setState(() => _endKind = v ?? 'never'),
            ),
            if (_endKind == 'afterCount') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _count,
                decoration:
                    const InputDecoration(labelText: 'Número de execuções'),
                keyboardType: TextInputType.number,
                validator: (v) => (int.tryParse(v?.trim() ?? '') ?? 0) < 1
                    ? 'Número inválido'
                    : null,
              ),
            ],
            if (_endKind == 'onDate')
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Data final'),
                subtitle:
                    Text('${_endDate.day}/${_endDate.month}/${_endDate.year}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickEndDate,
              ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pular se o terminal estiver ocupado'),
              value: _skipIfBusy,
              onChanged: (v) => setState(() => _skipIfBusy = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notificar ao disparar'),
              value: _notifyOnFire,
              onChanged: (v) => setState(() => _notifyOnFire = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ativa'),
              value: _isEnabled,
              onChanged: (v) => setState(() => _isEnabled = v),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Salvar')),
          ],
        ),
      ),
    );
  }

  List<Widget> _scheduleFields() {
    switch (_kind) {
      case 'once':
        return [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Quando'),
            subtitle: Text(
              '${_onceAt.day}/${_onceAt.month}/${_onceAt.year} '
              '${_onceAt.hour.toString().padLeft(2, '0')}:${_onceAt.minute.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.schedule),
            onTap: _pickOnceAt,
          ),
        ];
      case 'interval':
        return [
          TextFormField(
            controller: _interval,
            decoration:
                const InputDecoration(labelText: 'Intervalo em segundos'),
            keyboardType: TextInputType.number,
            validator: (v) => (int.tryParse(v?.trim() ?? '') ?? 0) < 1
                ? 'Use um número maior que zero'
                : null,
          ),
        ];
      case 'weekly':
        const names = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
        return [
          Wrap(
            spacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(names[d - 1]),
                  selected: _weekdays.contains(d),
                  onSelected: (sel) => setState(() {
                    sel ? _weekdays.add(d) : _weekdays.remove(d);
                  }),
                ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Horário'),
            subtitle: Text(_time.format(context)),
            trailing: const Icon(Icons.schedule),
            onTap: _pickTime,
          ),
        ];
      default:
        return [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Horário'),
            subtitle: Text(_time.format(context)),
            trailing: const Icon(Icons.schedule),
            onTap: _pickTime,
          ),
        ];
    }
  }
}

/// UUID v4 em maiúsculas, o formato que o Foundation imprime.
String _newId() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex =
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
