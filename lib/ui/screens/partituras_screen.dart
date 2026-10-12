import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../core/network/api_partituras.dart';
import '../../core/network/wire_client.dart';
import '../../models/floor.dart';
import '../../models/partitura.dart';

/// Biblioteca de partituras do host: lista, prévia e estampar em um andar.
///
/// Abra com `PartiturasScreen(client: client, workspaceId: ws, floors: floors)`.
/// [initialX] e [initialY] são o ponto central sugerido para estampar (ex.: o
/// centro da viewport do canvas). [onStamped] roda após uma estampa bem-sucedida.
/// Criar e editar partituras continuam no host.
class PartiturasScreen extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final List<FloorMeta> floors;
  final double initialX;
  final double initialY;
  final VoidCallback? onStamped;

  const PartiturasScreen({
    super.key,
    required this.client,
    required this.workspaceId,
    this.floors = const [],
    this.initialX = 0,
    this.initialY = 0,
    this.onStamped,
  });

  @override
  State<PartiturasScreen> createState() => _PartiturasScreenState();
}

class _PartiturasScreenState extends State<PartiturasScreen> {
  bool _loading = true;
  String? _loadError;
  List<Partitura> _items = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final items = await widget.client.listPartituras();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _open(Partitura p) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PartituraDetailScreen(
        client: widget.client,
        partitura: p,
        workspaceId: widget.workspaceId,
        floors: widget.floors,
        initialX: widget.initialX,
        initialY: widget.initialY,
        onStamped: widget.onStamped,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partituras'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _reload,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Não foi possível carregar as partituras.\n$_loadError',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _reload, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('Nenhuma partitura salva no host.'));
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final p = _items[i];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: PartituraThumbnail(
                        client: widget.client, partituraId: p.id),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall),
                        if (p.summary.isNotEmpty)
                          Text(p.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Miniatura da prévia do host. Busca uma vez por montagem, com ETag.
class PartituraThumbnail extends StatefulWidget {
  final WireClient client;
  final String partituraId;
  final String appearance;

  const PartituraThumbnail({
    super.key,
    required this.client,
    required this.partituraId,
    this.appearance = 'light',
  });

  @override
  State<PartituraThumbnail> createState() => _PartituraThumbnailState();
}

class _PartituraThumbnailState extends State<PartituraThumbnail> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Uint8List?> _load() async {
    final preview = await widget.client.fetchPartituraPreview(
      widget.partituraId,
      appearance: widget.appearance,
    );
    return preview.bytes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const ColoredBox(
              color: Color(0x11000000),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final bytes = snap.data;
        if (bytes == null) {
          return const ColoredBox(
              color: Color(0x11000000),
              child: Icon(Icons.image_not_supported_outlined));
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

/// Detalhe de uma partitura: prévia maior, responsabilidades embutidas e Estampar.
class PartituraDetailScreen extends StatefulWidget {
  final WireClient client;
  final Partitura partitura;
  final String workspaceId;
  final List<FloorMeta> floors;
  final double initialX;
  final double initialY;
  final VoidCallback? onStamped;

  const PartituraDetailScreen({
    super.key,
    required this.client,
    required this.partitura,
    required this.workspaceId,
    this.floors = const [],
    this.initialX = 0,
    this.initialY = 0,
    this.onStamped,
  });

  @override
  State<PartituraDetailScreen> createState() => _PartituraDetailScreenState();
}

class _PartituraDetailScreenState extends State<PartituraDetailScreen> {
  String? _floorId;
  late final TextEditingController _xController;
  late final TextEditingController _yController;
  bool _stamping = false;

  @override
  void initState() {
    super.initState();
    final floors = _stampableFloors;
    _floorId = floors.isNotEmpty ? floors.first.id : null;
    _xController = TextEditingController(text: widget.initialX.toString());
    _yController = TextEditingController(text: widget.initialY.toString());
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    super.dispose();
  }

  List<FloorMeta> get _stampableFloors =>
      widget.floors.where((f) => f.id != null).toList();

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stamp() async {
    final x = double.tryParse(_xController.text.trim().replaceAll(',', '.'));
    final y = double.tryParse(_yController.text.trim().replaceAll(',', '.'));
    if (x == null || y == null || !x.isFinite || !y.isFinite) {
      _snack('Informe X e Y numéricos.');
      return;
    }
    if (_floorId == null) {
      _snack('Escolha um andar.');
      return;
    }
    final floorName = _stampableFloors.firstWhere((f) => f.id == _floorId).name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estampar partitura?'),
        content: Text(
            '"${widget.partitura.name}" será estampada no andar "$floorName" '
            'em ($x, $y), criando os terminais do arranjo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Estampar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _stamping = true);
    try {
      await widget.client.stampPartitura(
        workspaceId: widget.workspaceId,
        partituraId: widget.partitura.id,
        x: x,
        y: y,
        floorId: _floorId,
      );
      if (!mounted) return;
      _snack('Partitura estampada.');
      widget.onStamped?.call();
    } catch (e) {
      _snack('Não foi possível estampar: $e');
    } finally {
      if (mounted) setState(() => _stamping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.partitura;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child:
                  PartituraThumbnail(client: widget.client, partituraId: p.id),
            ),
          ),
          if (p.summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(p.summary, style: theme.textTheme.bodyMedium),
          ],
          if (p.roles.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Responsabilidades', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final r in p.roles) Chip(label: Text(r.name))],
            ),
          ],
          const SizedBox(height: 24),
          Text('Estampar em um andar', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_stampableFloors.isEmpty)
            const Text('Nenhum andar disponível para estampar.')
          else
            DropdownButtonFormField<String>(
              initialValue: _floorId,
              decoration: const InputDecoration(
                  labelText: 'Andar', border: OutlineInputBorder()),
              items: [
                for (final f in _stampableFloors)
                  DropdownMenuItem(value: f.id, child: Text(f.name)),
              ],
              onChanged: _stamping ? null : (v) => setState(() => _floorId = v),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _xController,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                      labelText: 'X', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _yController,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: const InputDecoration(
                      labelText: 'Y', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _stamping || _stampableFloors.isEmpty ? null : _stamp,
            icon: _stamping
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.place_outlined),
            label: const Text('Estampar'),
          ),
        ],
      ),
    );
  }
}
