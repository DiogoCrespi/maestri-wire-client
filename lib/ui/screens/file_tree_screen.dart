import 'dart:convert';

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_file_tree.dart';
import '../../core/network/wire_client.dart';
import '../../models/file_tree.dart';

/// Navegador de uma árvore de arquivos (nó `fileTree` do canvas).
///
/// Abas: "Arquivos" (pastas, busca e leitura de arquivos texto) e "Mudanças"
/// (arquivos alterados do repositório, com diff). Só owner; um guest recebe
/// `403` do host e a tela mostra o erro.
class FileTreeScreen extends StatelessWidget {
  final WireClient client;
  final String workspaceId;
  final String nodeId;
  final String title;
  /// Mostra arquivos ocultos ao abrir; o botão da barra alterna depois.
  final bool initiallyShowHidden;

  const FileTreeScreen({
    super.key,
    required this.client,
    required this.workspaceId,
    required this.nodeId,
    required this.title,
    this.initiallyShowHidden = false,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          title: Text(title),
          bottom: const TabBar(
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.neonViolet,
            tabs: [Tab(text: 'Arquivos'), Tab(text: 'Mudanças')],
          ),
        ),
        body: TabBarView(
          children: [
            _FilesTab(
              client: client,
              workspaceId: workspaceId,
              nodeId: nodeId,
              rootName: title,
              initiallyShowHidden: initiallyShowHidden,
            ),
            _ChangesTab(client: client, workspaceId: workspaceId, nodeId: nodeId),
          ],
        ),
      ),
    );
  }
}

class _FilesTab extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final String nodeId;
  final String rootName;
  final bool initiallyShowHidden;

  const _FilesTab({
    required this.client,
    required this.workspaceId,
    required this.nodeId,
    required this.rootName,
    required this.initiallyShowHidden,
  });

  @override
  State<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<_FilesTab> {
  late final FileTreeCrumbs _crumbs = FileTreeCrumbs(widget.rootName);
  final _searchController = TextEditingController();
  FileTreeListing? _listing;
  FileTreeSearch? _search;
  String? _error;
  bool _loading = false;
  late bool _showHidden = widget.initiallyShowHidden;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await widget.client.getFileTreeListing(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
        path: _crumbs.current.path,
        hidden: _showHidden,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _listing = listing;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = _describe(e);
        _loading = false;
      });
    }
  }

  Future<void> _runSearch(String query) async {
    final text = query.trim();
    if (text.isEmpty) {
      setState(() => _search = null);
      return;
    }
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.client.searchFileTree(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
        query: text,
        hidden: _showHidden,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _search = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = _describe(e);
        _loading = false;
      });
    }
  }

  void _open(FileTreeEntry entry) {
    if (entry.isDirectory) {
      setState(() {
        _crumbs.push(entry);
        _search = null;
        _searchController.clear();
      });
      _load();
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _FileViewScreen(
          client: widget.client,
          workspaceId: widget.workspaceId,
          nodeId: widget.nodeId,
          entry: entry,
        ),
      ));
    }
  }

  void _openSearchFolder(FileTreeEntry folder) {
    setState(() {
      _crumbs.resetTo(_crumbs.items.first.name, folder);
      _search = null;
      _searchController.clear();
    });
    _load();
  }

  void _jumpTo(int index) {
    setState(() {
      _crumbs.jumpTo(index);
      _search = null;
      _searchController.clear();
    });
    _load();
  }

  void _toggleHidden() {
    setState(() => _showHidden = !_showHidden);
    _load();
  }

  String _describe(Object e) {
    if (e is FileTreeException) {
      if (e.statusCode == 404) return 'Pasta não encontrada.';
      if (e.statusCode == 403) return 'Sem permissão para esta árvore (só o dono).';
      return e.message;
    }
    return 'Não foi possível falar com o host: $e';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          crumbs: _crumbs.items,
          showHidden: _showHidden,
          onJump: _jumpTo,
          onToggleHidden: _toggleHidden,
          onRefresh: _load,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Buscar arquivos e pastas (Enter)',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
              isDense: true,
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onSubmitted: _runSearch,
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: AppColors.statusAlert)),
          ),
        Expanded(child: _search != null ? _buildSearch(_search!) : _buildListing()),
      ],
    );
  }

  Widget _buildListing() {
    final listing = _listing;
    if (listing == null) return const SizedBox.shrink();
    if (listing.entries.isEmpty) {
      return const Center(
        child: Text('Pasta vazia', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return ListView(
      children: [
        for (final e in listing.entries) _EntryTile(entry: e, onTap: () => _open(e)),
        if (listing.isTruncated)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Lista truncada pelo host.', style: TextStyle(color: AppColors.textMuted)),
          ),
      ],
    );
  }

  Widget _buildSearch(FileTreeSearch search) {
    if (search.hits.isEmpty) {
      return const Center(
        child: Text('Nada encontrado', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return ListView(
      children: [
        for (final e in search.hits)
          _EntryTile(
            entry: e,
            subtitle: e.path,
            onTap: () => e.isDirectory ? _openSearchFolder(e) : _open(e),
          ),
        if (search.isTruncated)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Mostrando os primeiros resultados.',
                style: TextStyle(color: AppColors.textMuted)),
          ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final List<FileTreeCrumb> crumbs;
  final bool showHidden;
  final ValueChanged<int> onJump;
  final VoidCallback onToggleHidden;
  final VoidCallback onRefresh;

  const _Toolbar({
    required this.crumbs,
    required this.showHidden,
    required this.onJump,
    required this.onToggleHidden,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0)
                      const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                    TextButton(
                      onPressed: () => onJump(i),
                      child: Text(
                        crumbs[i].name,
                        style: TextStyle(
                          color: i == crumbs.length - 1
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: showHidden ? 'Ocultar arquivos ocultos' : 'Mostrar arquivos ocultos',
            icon: Icon(showHidden ? Icons.visibility : Icons.visibility_off,
                color: AppColors.textSecondary),
            onPressed: onToggleHidden,
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final FileTreeEntry entry;
  final String? subtitle;
  final VoidCallback onTap;

  const _EntryTile({required this.entry, required this.onTap, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final status = entry.gitStatus;
    return ListTile(
      dense: true,
      leading: Icon(
        entry.isDirectory ? Icons.folder : Icons.insert_drive_file_outlined,
        color: entry.isDirectory ? AppColors.statusBusy : AppColors.textSecondary,
      ),
      title: Text(entry.name, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      trailing: status == null
          ? null
          : Text(status, style: const TextStyle(color: AppColors.statusWarning)),
      onTap: onTap,
    );
  }
}

/// Visualiza um arquivo texto em trechos de [_chunkSize] bytes, via `Range`.
class _FileViewScreen extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final String nodeId;
  final FileTreeEntry entry;

  const _FileViewScreen({
    required this.client,
    required this.workspaceId,
    required this.nodeId,
    required this.entry,
  });

  @override
  State<_FileViewScreen> createState() => _FileViewScreenState();
}

class _FileViewScreenState extends State<_FileViewScreen> {
  static const int _chunkSize = 256 * 1024;

  final List<int> _bytes = [];
  int? _total;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNext();
  }

  Future<void> _loadNext() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final start = _bytes.length;
    try {
      final chunk = await widget.client.getFileTreeBytes(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
        path: widget.entry.path,
        start: start,
        end: start + _chunkSize - 1,
      );
      if (!mounted) return;
      setState(() {
        _bytes.addAll(chunk.bytes);
        _total = chunk.totalLength ?? _total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is FileTreeException ? e.message : 'Falha ao ler o arquivo: $e';
        _loading = false;
      });
    }
  }

  bool get _hasMore => _total != null ? _bytes.length < _total! : false;

  @override
  Widget build(BuildContext context) {
    final text = utf8.decode(_bytes, allowMalformed: true);
    return Scaffold(
      backgroundColor: AppColors.terminalBg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.entry.name, overflow: TextOverflow.ellipsis),
            if (_total != null)
              Text(
                '${_bytes.length} de $_total bytes',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
      body: _error != null && _bytes.isEmpty
          ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.statusAlert)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: const TextStyle(color: AppColors.statusAlert)),
                    ),
                  if (_hasMore)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton(
                        onPressed: _loading ? null : _loadNext,
                        child: Text(_loading ? 'Carregando...' : 'Carregar mais'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Lista de mudanças do repositório da raiz (staged e unstaged).
class _ChangesTab extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final String nodeId;

  const _ChangesTab({required this.client, required this.workspaceId, required this.nodeId});

  @override
  State<_ChangesTab> createState() => _ChangesTabState();
}

class _ChangesTabState extends State<_ChangesTab> {
  FileTreeChanges? _changes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final changes = await widget.client.getFileTreeChanges(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
      );
      if (!mounted) return;
      setState(() {
        _changes = changes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is FileTreeException && e.statusCode == 404
            ? 'Esta pasta não está dentro de um repositório git.'
            : (e is FileTreeException ? e.message : 'Falha ao ler mudanças: $e');
        _loading = false;
      });
    }
  }

  void _openDiff(FileTreeChange change) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DiffScreen(
        client: widget.client,
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
        change: change,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    final changes = _changes!;
    final rows = <Widget>[
      if (changes.branch != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Branch: ${changes.branch}',
              style: const TextStyle(color: AppColors.textAccent)),
        ),
      ..._section('Staged', changes.staged),
      ..._section('Não staged', changes.unstaged),
      if (changes.staged.isEmpty && changes.unstaged.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nenhuma mudança', style: TextStyle(color: AppColors.textMuted)),
        ),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: rows),
    );
  }

  List<Widget> _section(String title, List<FileTreeChange> items) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text('$title (${items.length})',
            style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ),
      for (final c in items)
        ListTile(
          dense: true,
          leading: Text(c.status,
              style: const TextStyle(color: AppColors.statusWarning, fontFamily: 'monospace')),
          title: Text(c.name, style: const TextStyle(color: AppColors.textPrimary)),
          subtitle: Text(c.directory.isEmpty ? c.path : c.directory,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          trailing: (c.additions != null || c.deletions != null)
              ? Text('+${c.additions ?? 0} -${c.deletions ?? 0}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))
              : null,
          onTap: () => _openDiff(c),
        ),
    ];
  }
}

/// Diff unificado de um arquivo alterado.
class _DiffScreen extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final String nodeId;
  final FileTreeChange change;

  const _DiffScreen({
    required this.client,
    required this.workspaceId,
    required this.nodeId,
    required this.change,
  });

  @override
  State<_DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<_DiffScreen> {
  FileTreeDiff? _diff;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scope = widget.change.isStaged ? FileTreeDiffScope.staged : FileTreeDiffScope.unstaged;
    try {
      final diff = await widget.client.getFileTreeDiff(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
        path: widget.change.path,
        scope: scope,
      );
      if (!mounted) return;
      setState(() => _diff = diff);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is FileTreeException ? e.message : 'Falha ao ler o diff: $e');
    }
  }

  Color _lineColor(String line) {
    if (line.startsWith('+') && !line.startsWith('+++')) return AppColors.statusActive;
    if (line.startsWith('-') && !line.startsWith('---')) return AppColors.statusAlert;
    if (line.startsWith('@@')) return AppColors.textAccent;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final diff = _diff;
    return Scaffold(
      backgroundColor: AppColors.terminalBg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Text(widget.change.name, overflow: TextOverflow.ellipsis),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.statusAlert)))
          : diff == null
              ? const Center(child: CircularProgressIndicator())
              : diff.patch.trim().isEmpty
                  ? const Center(
                      child: Text('Sem diff', style: TextStyle(color: AppColors.textMuted)))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: SelectableText.rich(
                          TextSpan(
                            children: [
                              for (final line in diff.patch.split('\n'))
                                TextSpan(
                                  text: '$line\n',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    color: _lineColor(line),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
    );
  }
}
