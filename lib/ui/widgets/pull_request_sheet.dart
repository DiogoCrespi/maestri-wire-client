import 'package:flutter/material.dart';
import '../../core/network/api_floors.dart';
import '../../models/floor.dart';
import '../../models/pull_request.dart';
import '../../state/wire_controller.dart';
import 'floor_selector.dart';

/// Folha de pull request do andar: contexto, abrir, verificar, enviar, merge,
/// remover, perguntar a um agente e esquecer. Cada ação é a rota do host; um
/// erro do host aparece aqui com as palavras dele e a folha continua aberta.
Future<void> showPullRequestSheet(
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
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: PullRequestSheet(controller: controller, floor: floor),
      ),
    ),
  );
}

class PullRequestSheet extends StatefulWidget {
  final WireController controller;
  final FloorMeta floor;

  const PullRequestSheet({super.key, required this.controller, required this.floor});

  @override
  State<PullRequestSheet> createState() => _PullRequestSheetState();
}

class _PullRequestSheetState extends State<PullRequestSheet> {
  PullRequestContext? _context;
  String? _contextError;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _info;

  // Formulário de abrir
  late final TextEditingController _base = TextEditingController();
  late final TextEditingController _title = TextEditingController();
  late final TextEditingController _body = TextEditingController();
  bool _draft = false;

  String _mergeMethod = pullRequestMergeMethods.first;

  FloorMeta get floor {
    for (final f in widget.controller.floors) {
      if (f.queryValue == widget.floor.queryValue) return f;
    }
    return widget.floor;
  }
  FloorPullRequest? get pr => floor.pullRequest;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _base.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() {
      _loading = true;
      _contextError = null;
    });
    try {
      final ctx = await widget.controller.getPullRequestContext(floor);
      if (!mounted) return;
      setState(() {
        _context = ctx;
        if (_base.text.isEmpty) _base.text = ctx.base;
        if (_title.text.isEmpty) _title.text = ctx.title;
        if (_body.text.isEmpty) _body.text = ctx.body;
      });
    } catch (e) {
      if (mounted) setState(() => _contextError = hostErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Roda uma ação do host, uma por vez. Erro fica na folha.
  Future<T?> _act<T>(Future<T> Function() action, {String? success}) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final result = await action();
      if (mounted && success != null) setState(() => _info = success);
      return result;
    } catch (e) {
      if (mounted) setState(() => _error = hostErrorText(e));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final base = _base.text.trim();
    final title = _title.text.trim();
    if (base.isEmpty || title.isEmpty) {
      setState(() => _error = 'Informe a base e o título.');
      return;
    }
    final opened = await _act(
      () => widget.controller.openPullRequest(
        floor,
        base: base,
        title: title,
        body: _body.text,
        draft: (_context?.supportsDraft ?? false) ? _draft : null,
      ),
      success: 'Pull request aberto.',
    );
    if (opened != null && opened.url != null && mounted) {
      setState(() => _info = 'Pull request aberto. Página: ${opened.url}');
    }
  }

  Future<bool> _confirm(String title, String body) async {
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

  Future<void> _confirmAndRun({
    required String title,
    required String body,
    required Future<void> Function() action,
    required String success,
  }) async {
    if (!await _confirm(title, body)) return;
    await _act(action, success: success);
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _error = null);
    try {
      setState(() => _busy = true);
      final removed = await widget.controller.removePullRequest(floor);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(removed.mergedInto != null
            ? 'Andar removido; trabalho em ${removed.mergedInto}.'
            : 'Andar removido; branch ${removed.branch ?? ''} preservado.'),
      ));
    } on FloorApiException catch (e) {
      if (e.statusCode == 412 && mounted) {
        // Trabalho extra no andar: pede confirmação com as palavras do host
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remover mesmo assim?'),
            content: Text('${e.message}\n\nO andar tem trabalho que o pull request não tem.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remover'),
              ),
            ],
          ),
        );
        if (ok == true && mounted) {
          try {
            final removed = await widget.controller.removePullRequest(floor, confirmExtraWork: true);
            if (!mounted) return;
            Navigator.of(context).pop();
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
              content: Text('Andar removido; branch ${removed.branch ?? ''} preservado.'),
            ));
          } catch (e2) {
            if (mounted) setState(() => _error = hostErrorText(e2));
          }
        }
      } else if (mounted) {
        setState(() => _error = hostErrorText(e));
      }
    } catch (e) {
      if (mounted) setState(() => _error = hostErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handOff() async {
    final agents = _context?.agents ?? const <PullRequestAgent>[];
    if (agents.isEmpty) return;
    final isReview = pr?.isReview ?? false;
    final isReadOnly = pr?.isReadOnly ?? false;
    final tasks = [
      if (!isReadOnly) ...['review', 'checks', 'conflicts'],
      if (isReview) 'assess',
    ];
    if (tasks.isEmpty) {
      setState(() => _error = 'Este andar não aceita essa pergunta agora.');
      return;
    }
    var agentId = agents.first.id;
    var task = tasks.first;
    final note = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Perguntar a um agente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: agentId,
                decoration: const InputDecoration(labelText: 'Agente'),
                items: [
                  for (final a in agents)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(a.isRunning ? a.name : '${a.name} (parado)'),
                    ),
                ],
                onChanged: (v) => setLocal(() => agentId = v ?? agentId),
              ),
              DropdownButtonFormField<String>(
                initialValue: task,
                decoration: const InputDecoration(labelText: 'Tarefa'),
                items: [
                  for (final t in tasks)
                    DropdownMenuItem(value: t, child: Text(pullRequestTaskLabel(t))),
                ],
                onChanged: (v) => setLocal(() => task = v ?? task),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
          ],
        ),
      ),
    );
    final noteText = note.text;
    note.dispose();
    if (ok != true) return;
    await _act(
      () => widget.controller.handOffPullRequest(
        floor,
        terminalId: agentId,
        task: task,
        note: noteText,
      ),
      success: 'Pergunta enviada ao agente.',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reconstrói quando o controlador recebe o feed novo (ex.: depois de abrir o PR)
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final ctx = _context;
        final pr = this.pr;
        final isReadOnly = pr?.isReadOnly ?? false;
        final isOpen = pr != null && (pr.state == null || pr.state == 'open');
        // isOpen implica pr != null (promoção do analisador)
        final canMerge = isOpen && !pr.isDraft && !_busy;
        return _buildBody(context, theme, ctx, pr, isReadOnly, isOpen, canMerge);
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    PullRequestContext? ctx,
    FloorPullRequest? pr,
    bool isReadOnly,
    bool isOpen,
    bool canMerge,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pull request de "${floor.name}"', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_loading && ctx == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_contextError != null && ctx == null)
          Text(_contextError!, style: TextStyle(color: theme.colorScheme.error))
        else if (pr != null) ...[
          _PrSummary(pr: pr, providerName: ctx?.providerName),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _act(() => widget.controller.checkPullRequest(floor),
                        success: 'Verificação pedida ao host.'),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Verificar'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || isReadOnly
                    ? null
                    : () => _act(() => widget.controller.pushPullRequest(floor),
                        success: 'Commits enviados ao pull request.'),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Enviar'),
              ),
              if (ctx != null && ctx.agents.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _handOff,
                  icon: const Icon(Icons.forum_outlined, size: 18),
                  label: const Text('Perguntar a um agente'),
                ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm(
                          'Remover andar?',
                          'O andar sai do host; o branch fica preservado.',
                        )) {
                          await _remove();
                        }
                      },
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Remover andar'),
              ),
              if (pr.state == 'closed')
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _confirmAndRun(
                            title: 'Esquecer o pull request?',
                            body: 'O andar deixa de acompanhar o pull request fechado.',
                            action: () => widget.controller.forgetPullRequest(floor),
                            success: 'Pull request esquecido.',
                          ),
                  icon: const Icon(Icons.history_toggle_off_rounded, size: 18),
                  label: const Text('Esquecer'),
                ),
            ],
          ),
          if (isOpen) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                DropdownButton<String>(
                  value: _mergeMethod,
                  items: [
                    for (final m in pullRequestMergeMethods)
                      DropdownMenuItem(value: m, child: Text(pullRequestMergeLabel(m))),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _mergeMethod = v ?? _mergeMethod),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: canMerge
                      ? () => _confirmAndRun(
                            title: 'Fazer merge?',
                            body: 'Merge (${pullRequestMergeLabel(_mergeMethod)}) no pull request '
                                '#${pr.number ?? '?'}. O host recusa um método que o provedor não oferece.',
                            action: () => widget.controller.mergePullRequest(floor, method: _mergeMethod),
                            success: 'Merge pedido ao host.',
                          )
                      : null,
                  child: Text(pr.isDraft ? 'Rascunho: não dá merge' : 'Fazer merge'),
                ),
              ],
            ),
          ],
          const Divider(height: 24),
        ] else if (ctx != null) ...[
          Text('Nenhum pull request ligado a este andar.', style: theme.textTheme.bodyMedium),
          if (ctx.problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(ctx.problem!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (ctx.problem == null) ...[
            const SizedBox(height: 8),
            Text(
              'Abre pelo ${ctx.providerName ?? 'site do projeto'}'
              '${ctx.account == null ? '' : ' (${ctx.account})'}'
              '${ctx.unpushedCommits == null ? '' : ' · ${ctx.unpushedCommits} commit(s) a enviar'}.',
              style: theme.textTheme.bodySmall,
            ),
            TextField(
              controller: _base,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Base'),
            ),
            TextField(
              controller: _title,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            TextField(
              controller: _body,
              enabled: !_busy,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Descrição'),
            ),
            if (ctx.supportsDraft)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rascunho'),
                value: _draft,
                onChanged: _busy ? null : (v) => setState(() => _draft = v),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _open,
              icon: const Icon(Icons.call_split_rounded, size: 18),
              label: const Text('Fazer push e abrir'),
            ),
          ],
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
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

class _PrSummary extends StatelessWidget {
  final FloorPullRequest pr;
  final String? providerName;

  const _PrSummary({required this.pr, this.providerName});

  static String stateLabel(String? state) {
    switch (state) {
      case 'open':
        return 'Aberto';
      case 'merged':
        return 'Mesclado';
      case 'closed':
        return 'Fechado';
      default:
        return 'Sincronizando';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attention = FloorPullRequestLine.attentionLabel(pr.attention);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${pr.number == null ? 'Sem número' : '#${pr.number}'}'
          '${pr.title == null ? '' : ' · ${pr.title}'}',
          style: theme.textTheme.bodyLarge,
        ),
        Text(
          [
            stateLabel(pr.state),
            if (pr.isDraft) 'rascunho',
            if (attention.isNotEmpty) attention,
            if (pr.isReview) 'revisão',
            if (pr.isReadOnly) 'somente leitura',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        if (pr.url != null)
          SelectableText(pr.url!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
