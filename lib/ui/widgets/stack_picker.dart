import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_notes.dart';
import '../../core/network/wire_client.dart';
import '../../models/note_stack.dart';
import '../screens/note_stack_screen.dart' show noteColorValue;

/// Escolha das notas de uma seleção do canvas para "Colocar no fichário".
///
/// Quem chama (a tela principal) passa as notas selecionadas. A folha deixa desmarcar
/// alguma (mínimo de 2) e então faz `POST …/note-stacks {nodeIds}`.
/// Devolve o `stackNodeId` criado (via `Navigator.pop`), ou null se cancelado.
///
/// Uso: `final id = await showStackPicker(context, client: c, workspaceId: ws, notes: selected);`
/// e, com `id != null`, abrir `NoteStackScreen(stackNodeId: id, …)`.
Future<String?> showStackPicker(
  BuildContext context, {
  required WireClient client,
  required String workspaceId,
  required List<NoteCandidate> notes,
  String? floorId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    builder: (_) => StackPickerSheet(
      client: client,
      workspaceId: workspaceId,
      notes: notes,
      floorId: floorId,
    ),
  );
}

/// Função pura: ids que vão para o fichário, na ordem da seleção, sem duplicar.
/// Um fichário precisa de ao menos duas notas.
List<String> stackPickerSelection(List<NoteCandidate> notes, Set<String> unchecked) {
  final seen = <String>{};
  return [
    for (final n in notes)
      if (!unchecked.contains(n.nodeId) && seen.add(n.nodeId)) n.nodeId,
  ];
}

class StackPickerSheet extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final List<NoteCandidate> notes;
  final String? floorId;

  const StackPickerSheet({
    super.key,
    required this.client,
    required this.workspaceId,
    required this.notes,
    this.floorId,
  });

  @override
  State<StackPickerSheet> createState() => _StackPickerSheetState();
}

class _StackPickerSheetState extends State<StackPickerSheet> {
  final Set<String> _unchecked = {};
  bool _busy = false;

  List<String> get _selected => stackPickerSelection(widget.notes, _unchecked);

  Future<void> _create() async {
    final ids = _selected;
    if (ids.length < 2 || _busy) return;
    setState(() => _busy = true);
    try {
      final stackId = await widget.client.createNoteStack(
        workspaceId: widget.workspaceId,
        nodeIds: ids,
        floorId: widget.floorId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(stackId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível criar o fichário: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    return SafeArea(
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Colocar no fichário',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                  TextButton(
                    onPressed: (count < 2 || _busy) ? null : _create,
                    child: Text(_busy ? 'Criando…' : 'Juntar ($count)'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final n in widget.notes)
                    CheckboxListTile(
                      value: !_unchecked.contains(n.nodeId),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                if (v == true) {
                                  _unchecked.remove(n.nodeId);
                                } else {
                                  _unchecked.add(n.nodeId);
                                }
                              }),
                      secondary: CircleAvatar(radius: 6, backgroundColor: noteColorValue(n.color)),
                      title: Text(n.title.isEmpty ? 'Sem título' : n.title,
                          style: const TextStyle(color: AppColors.textPrimary)),
                      subtitle: n.floorName == null
                          ? null
                          : Text(n.floorName!, style: const TextStyle(color: AppColors.textMuted)),
                    ),
                ],
              ),
            ),
            if (count < 2)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Escolha ao menos duas notas.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
