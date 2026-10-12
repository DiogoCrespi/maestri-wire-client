import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/wire_client.dart';
import '../../core/network/api_notes.dart';
import '../../models/note_content.dart';
import '../../models/note_stack.dart';
import 'note_stack_screen.dart';

/// Edição de uma nota do canvas com proteção contra sobrescrita (ifRevision).
class NoteScreen extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final String nodeId;
  final String title;

  /// Mutações ao vivo do feed (o `kind` de cada `MutationEvent`), empurradas pelo
  /// controlador. Um `{'kind': 'feedSnapshot'}` manda reler a trava (ela não vira mutação).
  final Stream<Map<String, dynamic>>? remoteChanges;

  const NoteScreen({
    Key? key,
    required this.client,
    required this.workspaceId,
    required this.nodeId,
    required this.title,
    this.remoteChanges,
  }) : super(key: key);

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  final TextEditingController _controller = TextEditingController();
  NoteContent? _loaded;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  String? _title;
  bool _togglingLock = false;
  StreamSubscription<Map<String, dynamic>>? _remoteSub;

  @override
  void initState() {
    super.initState();
    _remoteSub = widget.remoteChanges?.listen(_onRemote);
    _controller.addListener(() {
      if (!_dirty && _loaded != null && _controller.text != _loaded!.text) {
        setState(() => _dirty = true);
      }
    });
    _title = widget.title;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final note = await widget.client.getNote(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
      );
      if (!mounted) return;
      _controller.text = note.text;
      setState(() {
        _loaded = note;
        _dirty = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível abrir a nota: $e';
        _loading = false;
      });
    }
  }

  /// Mudança remota: recarrega em silêncio; com texto não salvo, só avisa e mantém o texto.
  void _onRemote(Map<String, dynamic> kind) {
    if (!mounted || _loading) return;
    if (kind['kind'] != kNoteFeedSnapshotKind && !isNoteRemoteChange(kind, {widget.nodeId})) {
      return;
    }
    if (_dirty && kind['kind'] != kNoteFeedSnapshotKind) {
      _snack('A nota mudou no host. Recarregar descarta o seu texto.');
      return;
    }
    _refreshSilently();
  }

  /// Relê a nota sem o spinner. Com texto não salvo, atualiza só a trava, nunca o texto
  /// nem a revisão (senão um salvar posterior sobrescreveria o host às cegas).
  Future<void> _refreshSilently() async {
    final loaded = _loaded;
    if (loaded == null) return;
    try {
      final note = await widget.client.getNote(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
      );
      if (!mounted) return;
      final current = _loaded;
      if (current == null) return;
      if (_dirty) {
        if (note.isLocked != current.isLocked) {
          setState(() => _loaded = current.withLocked(note.isLocked));
        }
        return;
      }
      if (note.revision != current.revision || note.isLocked != current.isLocked) {
        _controller.text = note.text;
        setState(() {
          _loaded = note;
          _dirty = false;
        });
      }
    } catch (_) {
      // Falha de rede numa releitura silenciosa: a tela segue com o que tem.
    }
  }

  /// Liga ou desliga a trava de conteúdo no host. Com texto não salvo, não trava:
  /// travar com edição pendente deixaria o texto sem onde ir.
  Future<void> _toggleLock() async {
    final loaded = _loaded;
    if (loaded == null || _saving || _togglingLock) return;
    if (!loaded.isLocked && _dirty) {
      _snack('Salve o texto antes de travar a nota.');
      return;
    }
    setState(() => _togglingLock = true);
    try {
      await widget.client.setContentLocked(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
        locked: !loaded.isLocked,
      );
      if (!mounted) return;
      await _refreshSilently();
      if (!mounted) return;
      _snack(loaded.isLocked ? 'Conteúdo destravado.' : 'Conteúdo travado.');
    } catch (e) {
      if (!mounted) return;
      _snack('Falha ao mudar a trava: $e');
    } finally {
      if (mounted) setState(() => _togglingLock = false);
    }
  }

  Future<void> _save() async {
    final loaded = _loaded;
    if (loaded == null || _saving) return;
    setState(() => _saving = true);
    try {
      final result = await widget.client.putNote(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
        text: _controller.text,
        ifRevision: loaded.revision,
      );
      if (!mounted) return;
      if (result.saved) {
        setState(() {
          _loaded = result.current;
          _dirty = false;
          _saving = false;
        });
        _snack('Nota salva.');
      } else if (result.locked) {
        setState(() => _saving = false);
        _snack('Nota travada no host. Destrave para editar.');
      } else if (result.conflict) {
        setState(() => _saving = false);
        await _resolveConflict(result.current);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Falha ao salvar: $e');
    }
  }

  /// O host mudou a nota enquanto ela estava aberta: escolhe recarregar ou sobrescrever.
  Future<void> _resolveConflict(NoteContent? current) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nota alterada no host'),
        content: const Text(
          'Alguém editou esta nota no host enquanto você escrevia. '
          'Recarregar descarta o seu texto; sobrescrever mantém o seu.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'reload'), child: const Text('Recarregar')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'overwrite'), child: const Text('Sobrescrever')),
        ],
      ),
    );
    if (!mounted || current == null) return;
    if (choice == 'reload') {
      _controller.text = current.text;
      setState(() {
        _loaded = current;
        _dirty = false;
      });
    } else if (choice == 'overwrite') {
      setState(() => _loaded = current);
      await _save();
    }
  }

  /// Renomeia a nota no host (POST nodes/{id}/rename). Não mexe no texto em edição.
  Future<void> _rename() async {
    final controller = TextEditingController(text: _title ?? widget.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renomear nota'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await widget.client.renameNode(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
        name: name,
      );
      if (!mounted) return;
      setState(() => _title = name);
      _snack('Nota renomeada.');
    } catch (e) {
      if (!mounted) return;
      _snack('Falha ao renomear: $e');
    }
  }

  /// Muda a cor da nota (PUT note/color). Cor é independente do texto.
  Future<void> _pickColor() async {
    final key = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in kNoteColorKeys)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, c),
                  child: CircleAvatar(radius: 18, backgroundColor: noteColorValue(c)),
                ),
            ],
          ),
        ),
      ),
    );
    if (key == null || !mounted) return;
    try {
      await widget.client.setNoteColor(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
        color: key,
      );
      if (!mounted) return;
      _snack('Cor da nota alterada.');
    } catch (e) {
      if (!mounted) return;
      _snack('Falha ao mudar a cor: $e');
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  void dispose() {
    _remoteSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _loaded?.isLocked ?? false;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(_title ?? widget.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        actions: [
          if (_loaded != null)
            IconButton(
              tooltip: 'Recarregar do host',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _loading ? null : _load,
            ),
          if (_loaded != null)
            IconButton(
              tooltip: locked ? 'Destravar conteúdo' : 'Travar conteúdo',
              icon: Icon(
                locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 20,
                color: locked ? AppColors.neonViolet : null,
              ),
              onPressed: (_loading || _saving || _togglingLock) ? null : _toggleLock,
            ),
          PopupMenuButton<String>(
            tooltip: 'Mais',
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            color: AppColors.surfaceElevated,
            enabled: _loaded != null && !_saving,
            onSelected: (v) {
              if (v == 'rename') _rename();
              if (v == 'color') _pickColor();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renomear')),
              PopupMenuItem(value: 'color', child: Text('Cor')),
            ],
          ),
          IconButton(
            tooltip: 'Salvar',
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.save_rounded, color: _dirty && !locked ? AppColors.neonViolet : AppColors.textMuted),
            onPressed: (_dirty && !locked && !_saving) ? _save : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: AppColors.textMuted)),
                  ),
                )
              : Column(
                  children: [
                    if (locked)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: AppColors.surfaceElevated,
                        child: const Row(
                          children: [
                            Icon(Icons.lock_rounded, size: 14, color: AppColors.textMuted),
                            SizedBox(width: 6),
                            Text('Conteúdo travado no host (somente leitura)',
                                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: _controller,
                          readOnly: locked,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Escreva em markdown…',
                            hintStyle: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
