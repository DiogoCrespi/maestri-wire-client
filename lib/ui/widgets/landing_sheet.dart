import 'package:flutter/material.dart';
import '../../core/network/api_floors.dart';
import '../../models/floor.dart';
import '../../state/wire_controller.dart';

/// Folha de aterrissagem: mostra a prévia (branches, arquivos, conflitos) antes
/// de trazer o branch do andar para o projeto. A prévia só lê; a aterrissagem
/// só acontece no botão, depois de confirmar.
Future<void> showLandingSheet(
  BuildContext context,
  WireController controller,
  FloorMeta floor,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: LandingSheet(controller: controller, floor: floor),
      ),
    ),
  );
}

class LandingSheet extends StatefulWidget {
  final WireController controller;
  final FloorMeta floor;

  const LandingSheet({super.key, required this.controller, required this.floor});

  @override
  State<LandingSheet> createState() => _LandingSheetState();
}

class _LandingSheetState extends State<LandingSheet> {
  FloorLanding? _preview;
  String? _target;
  bool _loading = true;
  String? _previewError;
  bool _landing = false;
  String? _landError;
  bool _deleteBranch = false;
  bool _keepFloor = false;

  @override
  void initState() {
    super.initState();
    _load(null);
  }

  /// Carrega a prévia. `target` null usa o alvo do próprio andar.
  Future<void> _load(String? target) async {
    setState(() {
      _loading = true;
      _previewError = null;
    });
    try {
      final preview = await widget.controller.getLandingPreview(widget.floor, target: target);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _target = preview.target ?? target;
      });
    } catch (e) {
      if (mounted) setState(() => _previewError = hostErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _land() async {
    final preview = _preview;
    final target = _target;
    if (preview == null || _landing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aterrissar andar?'),
        content: Text(
          preview.isMerge
              ? 'Faz merge de ${preview.branch ?? 'o branch do andar'} em ${target ?? 'o alvo'} '
                  '(${preview.commitCount} commit(s), ${preview.files.length} arquivo(s)).'
              : 'Traz ${preview.branch ?? 'o branch do andar'} para o projeto.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aterrissar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _landing = true;
      _landError = null;
    });
    try {
      await widget.controller.landFloor(
        widget.floor,
        targetBranch: target,
        deleteBranch: _deleteBranch,
        keepFloor: _keepFloor,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Andar aterrissado${target == null ? '' : ' em $target'}.')),
      );
    } catch (e) {
      // Recusa do host (ex.: trabalho não commitado, conflito): mostra e não tenta de novo
      if (mounted) setState(() => _landError = hostErrorText(e));
    } finally {
      if (mounted) setState(() => _landing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final floor = widget.floor;
    final preview = _preview;
    final hasConflicts = preview?.hasConflicts ?? false;
    final canLand = !_loading &&
        !_landing &&
        preview != null &&
        !hasConflicts &&
        floor.isGitIsolated;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Aterrissar "${floor.name}"', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!floor.isGitIsolated)
          Text(
            'Este andar não tem checkout git próprio: não há o que aterrissar.',
            style: theme.textTheme.bodyMedium,
          )
        else if (_loading && preview == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_previewError != null && preview == null)
          Text(_previewError!, style: TextStyle(color: theme.colorScheme.error))
        else if (preview != null) ...[
          _BranchRow(
            from: preview.branch ?? floor.branch ?? '?',
            branches: preview.branches,
            target: _target,
            enabled: !_loading && !_landing,
            onTarget: (t) => _load(t),
          ),
          const SizedBox(height: 4),
          Text(
            preview.isMerge
                ? 'Merge em ${_target ?? '?'}: ${preview.commitCount} commit(s).'
                : 'Só traz o branch para o projeto (sem merge).',
            style: theme.textTheme.bodySmall,
          ),
          if (preview.groundBranch != null)
            Text('Térreo em ${preview.groundBranch}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          if (hasConflicts)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Conflitos (${preview.conflicts.length}) — resolva antes de aterrissar:\n'
                '${preview.conflicts.join('\n')}',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          Text('Arquivos (${preview.files.length})', style: theme.textTheme.labelLarge),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
            child: preview.files.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Nenhuma diferença.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in preview.files)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text(
                            f.isBinary ? 'binário' : '+${f.additions} −${f.deletions}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Manter o andar'),
            subtitle: const Text('O andar continua trabalhando neste branch'),
            value: _keepFloor,
            onChanged: _landing ? null : (v) => setState(() => _keepFloor = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Excluir o branch do andar'),
            subtitle: Text(_keepFloor
                ? 'Ignorado enquanto o andar é mantido'
                : 'Melhor esforço, como o host faz'),
            value: _deleteBranch && !_keepFloor,
            onChanged: _landing || _keepFloor ? null : (v) => setState(() => _deleteBranch = v),
          ),
        ],
        if (_landError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_landError!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: canLand ? _land : null,
          icon: _landing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.merge_rounded),
          label: Text(hasConflicts ? 'Há conflitos' : 'Aterrissar'),
        ),
      ],
    );
  }
}

class _BranchRow extends StatelessWidget {
  final String from;
  final List<String> branches;
  final String? target;
  final bool enabled;
  final ValueChanged<String> onTarget;

  const _BranchRow({
    required this.from,
    required this.branches,
    required this.target,
    required this.enabled,
    required this.onTarget,
  });

  @override
  Widget build(BuildContext context) {
    // O alvo atual pode não estar na lista (ex.: vindo do próprio andar): inclui.
    final options = {...branches, if (target != null) target!}.toList();
    return Row(
      children: [
        Flexible(child: Text(from, overflow: TextOverflow.ellipsis)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded, size: 16),
        ),
        Expanded(
          child: options.isEmpty
              ? const Text('Sem branches')
              : DropdownButton<String>(
                  isExpanded: true,
                  value: target,
                  hint: const Text('Alvo'),
                  items: [
                    for (final b in options) DropdownMenuItem(value: b, child: Text(b)),
                  ],
                  onChanged: enabled ? (v) => v == null ? null : onTarget(v) : null,
                ),
        ),
      ],
    );
  }
}
