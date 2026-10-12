import 'package:flutter/material.dart';
import '../../core/network/api_floors.dart';
import '../../models/floor.dart';
import '../../state/wire_controller.dart';
import 'floor_selector.dart';

/// Progresso depois de trocar de estado: é mantido enquanto o estado não muda
/// e descartado quando ele muda (contrato: "Status do andar").
double? statusProgressFor({
  required String? initialState,
  required String newState,
  required double? initialProgress,
}) =>
    initialState == newState ? initialProgress : null;

/// Limite de caracteres do relato; o host corta acima de 120 Swift Characters.
const floorStatusTextLimit = 120;

/// Abre o editor de status do andar. Retorna true se gravou ou limpou.
Future<bool?> showFloorStatusEditor(
  BuildContext context,
  WireController controller,
  FloorMeta floor,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FloorStatusEditor(controller: controller, floor: floor),
        ),
      ),
    ),
  );
}

class FloorStatusEditor extends StatefulWidget {
  final WireController controller;
  final FloorMeta floor;

  const FloorStatusEditor({super.key, required this.controller, required this.floor});

  @override
  State<FloorStatusEditor> createState() => _FloorStatusEditorState();
}

class _FloorStatusEditorState extends State<FloorStatusEditor> {
  static const _states = [
    FloorStatus.working,
    FloorStatus.blocked,
    FloorStatus.review,
    FloorStatus.done,
  ];

  late final String? _initialState = widget.floor.status?.state;
  late final double? _initialProgress = widget.floor.status?.progress;
  late String _state = FloorStatus.knownStates.contains(_initialState)
      ? _initialState!
      : FloorStatus.working;
  late final TextEditingController _text =
      TextEditingController(text: widget.floor.status?.text ?? '');
  late double? _progress = statusProgressFor(
    initialState: _initialState,
    newState: _state,
    initialProgress: _initialProgress,
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pickState(String state) {
    setState(() {
      _progress = statusProgressFor(
        initialState: _initialState,
        newState: state,
        initialProgress: _initialProgress,
      );
      _state = state;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Editor continua aberto com a recusa do host
      if (mounted) setState(() => _error = hostErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasStatus = widget.floor.status != null;
    final text = _text.text.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Status de "${widget.floor.name}"', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final s in _states)
              ChoiceChip(
                label: Text(FloorStatusLine.stateLabel(s)),
                selected: _state == s,
                onSelected: _busy ? null : (_) => _pickState(s),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          enabled: !_busy,
          maxLength: floorStatusTextLimit,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Relato curto',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mostrar progresso'),
          subtitle: _progress == null
              ? const Text('Sem progresso')
              : Text('${(_progress! * 100).round()}%'),
          value: _progress != null,
          onChanged: _busy
              ? null
              : (on) => setState(() => _progress = on ? (_progress ?? 0) : null),
        ),
        if (_progress != null)
          Slider(
            value: _progress!,
            divisions: 20,
            label: '${(_progress! * 100).round()}%',
            onChanged: _busy ? null : (v) => setState(() => _progress = v),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (hasStatus)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.controller.clearFloorStatus(widget.floor)),
                icon: const Icon(Icons.clear_rounded),
                label: const Text('Limpar'),
              ),
            const Spacer(),
            FilledButton(
              onPressed: _busy || text.isEmpty
                  ? null
                  : () => _run(() => widget.controller.setFloorStatus(
                        widget.floor,
                        state: _state,
                        text: text,
                        progress: _progress,
                      )),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ],
    );
  }
}
