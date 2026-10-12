import 'package:flutter/material.dart';
import '../../core/network/api_devices.dart';
import '../../core/network/wire_client.dart';
import '../../models/device.dart';

/// Dispositivos pareados: lista, renomear, mudar papel (owner/guest) e revogar.
///
/// Abra com `DevicesScreen(client: client)`. Revogar e rebaixar pedem confirmação.
/// Revogar o próprio aparelho desconecta este cliente.
class DevicesScreen extends StatefulWidget {
  final WireClient client;

  const DevicesScreen({super.key, required this.client});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool _loading = true;
  String? _loadError;
  List<PairedDevice> _devices = const [];
  final Set<String> _busyIds = {};

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
      final devices = await widget.client.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
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

  bool _isSelf(PairedDevice d) {
    final me = widget.client.deviceId;
    return me != null && me.toUpperCase() == d.id.toUpperCase();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Roda uma ação sobre um dispositivo, com trava por id e recarga no fim.
  Future<bool> _act(PairedDevice d, Future<void> Function() action,
      String doneMessage) async {
    if (_busyIds.contains(d.id)) return false;
    setState(() => _busyIds.add(d.id));
    try {
      await action();
      _snack(doneMessage);
      await _reload();
      return true;
    } catch (e) {
      _snack('Não foi possível: $e');
      return false;
    } finally {
      if (mounted) setState(() => _busyIds.remove(d.id));
    }
  }

  Future<void> _rename(PairedDevice d) async {
    final controller = TextEditingController(text: d.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renomear dispositivo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Nome'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Salvar')),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final String clean;
    try {
      clean = normalizeDeviceName(name);
    } catch (e) {
      _snack('${(e as ArgumentError).message}');
      return;
    }
    if (clean == d.name) return;
    await _act(d, () => widget.client.renameDevice(d.id, clean),
        'Dispositivo renomeado.');
  }

  Future<void> _changeRole(PairedDevice d, String role) async {
    if (role == d.role) return;
    final toGuest = role == PairedDevice.roleGuest;
    final ok = await _confirm(
      title: toGuest ? 'Rebaixar para Somente leitura?' : 'Dar Controle total?',
      message: toGuest
          ? '"${d.name}" deixará de poder agir sobre agentes e o canvas.'
              '${_isSelf(d) ? ' Este aparelho perderá a capacidade de escrever.' : ''}'
          : '"${d.name}" poderá agir sobre agentes e o canvas.',
      confirmLabel: toGuest ? 'Rebaixar' : 'Dar controle',
    );
    if (!ok) return;
    await _act(
        d, () => widget.client.setDeviceRole(d.id, role), 'Papel atualizado.');
  }

  Future<void> _revoke(PairedDevice d) async {
    final self = _isSelf(d);
    final ok = await _confirm(
      title: 'Revogar dispositivo?',
      message: '"${d.name}" será desconectado e precisará parear de novo.'
          '${self ? ' Este é o aparelho atual: você sairá deste cliente.' : ''}',
      confirmLabel: 'Revogar',
      destructive: true,
    );
    if (!ok) return;
    await _act(
        d, () => widget.client.revokeDevice(d.id), 'Dispositivo revogado.');
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  String _roleLabel(String? role) => switch (role) {
        PairedDevice.roleOwner => 'Controle total',
        PairedDevice.roleGuest => 'Somente leitura',
        _ => 'Papel desconhecido',
      };

  String _lastSeen(PairedDevice d) {
    final at = d.lastSeenAt?.toLocal();
    if (at == null) return 'Nunca visto';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Visto em ${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}'
        '${d.lastSeenIP != null ? ' · ${d.lastSeenIP}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos'),
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
    if (_loading && _devices.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Não foi possível carregar os dispositivos.\n$_loadError',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _reload, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    if (_devices.isEmpty) {
      return const Center(child: Text('Nenhum dispositivo pareado.'));
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _devices.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final d = _devices[i];
          final busy = _busyIds.contains(d.id);
          return ListTile(
            leading: Icon(
                d.isGuest ? Icons.visibility_outlined : Icons.phone_android),
            title: Text(d.name + (_isSelf(d) ? ' (este aparelho)' : '')),
            subtitle: Text('${_roleLabel(d.role)} · ${_lastSeen(d)}'),
            trailing: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'rename':
                          _rename(d);
                        case 'owner':
                          _changeRole(d, PairedDevice.roleOwner);
                        case 'guest':
                          _changeRole(d, PairedDevice.roleGuest);
                        case 'revoke':
                          _revoke(d);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'rename', child: Text('Renomear')),
                      if (!d.isOwner)
                        const PopupMenuItem(
                            value: 'owner', child: Text('Dar Controle total')),
                      if (!d.isGuest)
                        const PopupMenuItem(
                            value: 'guest',
                            child: Text('Tornar Somente leitura')),
                      const PopupMenuItem(
                          value: 'revoke', child: Text('Revogar')),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
