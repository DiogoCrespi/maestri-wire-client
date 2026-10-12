import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_notes.dart';
import '../../core/network/wire_client.dart';
import '../../models/note_content.dart';
import '../../models/note_stack.dart';
import 'note_screen.dart';

/// Cor visual de uma cor de nota do host.
Color noteColorValue(String? key) {
  switch (key) {
    case 'blue':
      return const Color(0xFF3B82F6);
    case 'purple':
      return const Color(0xFF9653F4);
    case 'pink':
      return const Color(0xFFEC4899);
    case 'red':
      return const Color(0xFFEF4444);
    case 'orange':
      return const Color(0xFFF97316);
    case 'green':
      return const Color(0xFF10B981);
    case 'graphite':
      return const Color(0xFF6B7280);
    case 'yellow':
    default:
      return const Color(0xFFFACC15);
  }
}

/// Fichário do canvas: abas (páginas), página da frente, e as ações do host
/// (virar, reordenar, criar página em branco, arquivar, cor, renomear).
class NoteStackScreen extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final String stackNodeId;
  final String? title;

  /// Mutações ao vivo do feed (o `kind` de cada `MutationEvent`), empurradas pelo
  /// controlador. A tela relê o fichário quando alguma toca nele ou nas páginas.
  final Stream<Map<String, dynamic>>? remoteChanges;

  const NoteStackScreen({
    super.key,
    required this.client,
    required this.workspaceId,
    required this.stackNodeId,
    this.title,
    this.remoteChanges,
  });

  @override
  State<NoteStackScreen> createState() => _NoteStackScreenState();
}

class _NoteStackScreenState extends State<NoteStackScreen> {
  NoteStack? _stack;
  NoteContent? _front;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _remoteSub;

  @override
  void initState() {
    super.initState();
    _remoteSub = widget.remoteChanges?.listen(_onRemote);
    _load();
  }

  /// Mutação remota que toca o fichário ou uma de suas páginas: relê em silêncio.
  /// Durante uma ação local (`_busy`) ignora: a própria ação já relê.
  void _onRemote(Map<String, dynamic> kind) {
    if (!mounted || _busy || _loading) return;
    final watched = <String>{
      widget.stackNodeId,
      for (final t in _stack?.tabs ?? const <NoteStackTab>[]) t.nodeId,
    };
    if (isNoteRemoteChange(kind, watched)) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final stack = await widget.client.loadNoteStack(
        workspaceId: widget.workspaceId,
        stackNodeId: widget.stackNodeId,
      );
      if (!mounted) return;
      if (stack == null) {
        setState(() {
          _error = 'Este fichário não existe mais no canvas.';
          _loading = false;
        });
        return;
      }
      final frontId = stack.frontNoteId;
      final front = frontId == null
          ? null
          : await widget.client.getNote(workspaceId: widget.workspaceId, nodeId: frontId);
      if (!mounted) return;
      setState(() {
        _stack = stack;
        _front = front;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível abrir o fichário: $e';
        _loading = false;
      });
    }
  }

  /// Executa uma escrita, aplica o resultado local e mostra falhas.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack('Falha: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Traz para este fichário uma nota solta ou uma página de outro fichário
  /// (`PUT …/stack/pages/{noteId}`).
  Future<void> _bringNote() async {
    final stack = _stack;
    if (stack == null || _busy) return;
    final List<NoteCandidate> candidates;
    try {
      candidates = await widget.client.loadNoteCandidates(
        workspaceId: widget.workspaceId,
        exclude: {for (final t in stack.tabs) t.nodeId},
      );
    } catch (e) {
      _snack('Não foi possível listar as notas: $e');
      return;
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      _snack('Nenhuma nota para trazer.');
      return;
    }
    final picked = await showModalBottomSheet<NoteCandidate>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 420,
          child: ListView.builder(
            itemCount: candidates.length,
            itemBuilder: (_, i) {
              final c = candidates[i];
              return ListTile(
                leading: CircleAvatar(radius: 6, backgroundColor: noteColorValue(c.color)),
                title: Text(c.title.isEmpty ? 'Sem título' : c.title,
                    style: const TextStyle(color: AppColors.textPrimary)),
                subtitle: c.floorName == null ? null : Text(c.floorName!),
                onTap: () => Navigator.pop(ctx, c),
              );
            },
          ),
        ),
      ),
    );
    if (picked == null) return;
    await _run(() async {
      await widget.client.bringStackPage(
        workspaceId: widget.workspaceId,
        stackNodeId: widget.stackNodeId,
        noteId: picked.nodeId,
      );
      await _load(silent: true);
    });
  }

  Future<void> _selectTab(NoteStackTab tab) async {
    if (tab.nodeId == _stack?.frontNoteId) return;
    await _run(() async {
      final rail = await widget.client.setStackFront(
        workspaceId: widget.workspaceId,
        stackNodeId: widget.stackNodeId,
        frontNoteId: tab.nodeId,
      );
      final front = await widget.client.getNote(workspaceId: widget.workspaceId, nodeId: tab.nodeId);
      if (!mounted) return;
      setState(() {
        _stack = _stack?.withRail(rail);
        _front = front;
      });
    });
  }

  Future<void> _addPage() async {
    await _run(() async {
      await widget.client.addStackPage(
        workspaceId: widget.workspaceId,
        stackNodeId: widget.stackNodeId,
        afterNoteId: _stack?.frontNoteId,
      );
      await _load();
    });
  }

  Future<void> _archive(NoteStackTab tab) async {
    await _run(() async {
      final rail = await widget.client.archiveStackPage(
        workspaceId: widget.workspaceId,
        stackNodeId: widget.stackNodeId,
        noteId: tab.nodeId,
      );
      if (!mounted) return;
      setState(() => _stack = _stack?.withRail(rail));
      await _load();
    });
  }

  Future<void> _reorder() async {
    final stack = _stack;
    if (stack == null || stack.tabs.length < 2) return;
    final order = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (ctx) => _ReorderSheet(tabs: stack.tabs),
    );
    if (order == null) return;
    await _run(() async {
      final rail = await widget.client.reorderStackPages(
        workspaceId: widget.workspaceId,
        stackNodeId: widget.stackNodeId,
        memberNodeIds: order,
      );
      if (!mounted) return;
      setState(() => _stack = _stack?.withRail(rail));
    });
  }

  Future<void> _pickColor(NoteStackTab tab) async {
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
    if (key == null) return;
    await _run(() async {
      await widget.client.setNoteColor(
        workspaceId: widget.workspaceId,
        nodeId: tab.nodeId,
        color: key,
      );
      if (!mounted) return;
      setState(() => _stack = _stack?.withTabColor(tab.nodeId, key));
      if (tab.nodeId == _stack?.frontNoteId) await _load();
    });
  }

  Future<String?> _askText(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
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
    return result;
  }

  Future<void> _renameTab(NoteStackTab tab) async {
    final name = await _askText('Renomear página', tab.title);
    if (name == null || name.isEmpty) return;
    await _run(() async {
      await widget.client.renameNode(
        workspaceId: widget.workspaceId,
        nodeId: tab.nodeId,
        name: name,
      );
      await _load();
    });
  }

  Future<void> _renameStack() async {
    final current = _stack?.name ?? '';
    final name = await _askText('Renomear fichário', current);
    if (name == null || name.isEmpty) return;
    await _run(() async {
      await widget.client.renameNode(
        workspaceId: widget.workspaceId,
        nodeId: widget.stackNodeId,
        name: name,
      );
      await _load();
    });
  }

  Future<void> _tabMenu(NoteStackTab tab) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_rounded),
              title: const Text('Trazer para a frente'),
              onTap: () => Navigator.pop(ctx, 'front'),
            ),
            ListTile(
              leading: const Icon(Icons.circle, color: AppColors.textSecondary),
              title: const Text('Cor'),
              onTap: () => Navigator.pop(ctx, 'color'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Renomear'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.archive_rounded),
              title: const Text('Tirar do fichário'),
              onTap: () => Navigator.pop(ctx, 'archive'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'front':
        await _selectTab(tab);
      case 'color':
        await _pickColor(tab);
      case 'rename':
        await _renameTab(tab);
      case 'archive':
        await _archive(tab);
    }
  }

  Future<void> _openFront() async {
    final front = _stack?.frontNoteId;
    if (front == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteScreen(
          client: widget.client,
          workspaceId: widget.workspaceId,
          nodeId: front,
          title: _front?.displayName ?? 'Nota',
          remoteChanges: widget.remoteChanges,
        ),
      ),
    );
    if (mounted) await _load(silent: true);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  void dispose() {
    _remoteSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stack = _stack;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          stack?.displayTitle ?? widget.title ?? 'Fichário',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (stack != null) ...[
            IconButton(
              tooltip: 'Nova página em branco',
              icon: const Icon(Icons.note_add_rounded, size: 20),
              onPressed: _busy ? null : _addPage,
            ),
            IconButton(
              tooltip: 'Reordenar páginas',
              icon: const Icon(Icons.swap_vert_rounded, size: 20),
              onPressed: _busy ? null : _reorder,
            ),
            IconButton(
              tooltip: 'Trazer nota para o fichário',
              icon: const Icon(Icons.move_to_inbox_rounded, size: 20),
              onPressed: _busy ? null : _bringNote,
            ),
            IconButton(
              tooltip: 'Renomear fichário',
              icon: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
              onPressed: _busy ? null : _renameStack,
            ),
          ],
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: (_loading || _busy) ? null : _load,
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
                    SizedBox(
                      height: 52,
                      child: stack == null || stack.tabs.isEmpty
                          ? const Center(
                              child: Text('Sem páginas', style: TextStyle(color: AppColors.textMuted)),
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: stack.tabs.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final tab = stack.tabs[i];
                                final isFront = tab.nodeId == stack.frontNoteId;
                                return GestureDetector(
                                  onTap: _busy ? null : () => _selectTab(tab),
                                  onLongPress: _busy ? null : () => _tabMenu(tab),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isFront ? AppColors.surfaceHover : AppColors.surfaceElevated,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isFront ? AppColors.neonViolet : AppColors.border,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: noteColorValue(tab.color),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 160),
                                          child: Text(
                                            tab.title.isEmpty ? 'Sem título' : tab.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: isFront ? AppColors.textPrimary : AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: _front == null
                          ? const Center(
                              child: Text('Nenhuma página na frente',
                                  style: TextStyle(color: AppColors.textMuted)),
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(
                                _front!.text.isEmpty ? '(nota vazia)' : _front!.text,
                                style: const TextStyle(
                                    fontSize: 14, height: 1.5, color: AppColors.textPrimary),
                              ),
                            ),
                    ),
                  ],
                ),
      floatingActionButton: (stack != null && _front != null)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.neonViolet,
              onPressed: _busy ? null : _openFront,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Editar'),
            )
          : null,
    );
  }
}

/// Folha para reordenar as abas. Devolve a nova ordem de `memberNodeIds`.
class _ReorderSheet extends StatefulWidget {
  final List<NoteStackTab> tabs;
  const _ReorderSheet({required this.tabs});

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  final List<NoteStackTab> _items = [];

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.tabs);
  }

  @override
  Widget build(BuildContext context) {
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
                    child: Text('Reordenar páginas',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _items.map((t) => t.nodeId).toList()),
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: _items.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final item = _items.removeAt(oldIndex);
                    _items.insert(newIndex, item);
                  });
                },
                itemBuilder: (_, i) {
                  final tab = _items[i];
                  return ListTile(
                    key: ValueKey(tab.nodeId),
                    leading: CircleAvatar(radius: 6, backgroundColor: noteColorValue(tab.color)),
                    title: Text(tab.title.isEmpty ? 'Sem título' : tab.title,
                        style: const TextStyle(color: AppColors.textPrimary)),
                    trailing: const Icon(Icons.drag_handle_rounded, color: AppColors.textMuted),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
