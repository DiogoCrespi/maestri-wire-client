import 'package:flutter/material.dart';
import '../../core/network/api_terminals.dart';
import '../../core/network/wire_client.dart';
import '../../models/agent_preset.dart';

/// Presets de agente do host, somente leitura (`GET /api/agent-presets`).
/// Para criar ou editar presets, use o host.
///
/// Abra com `PresetsScreen(client: client)`.
class PresetsScreen extends StatefulWidget {
  final WireClient client;

  const PresetsScreen({super.key, required this.client});

  @override
  State<PresetsScreen> createState() => _PresetsScreenState();
}

class _PresetsScreenState extends State<PresetsScreen> {
  bool _loading = true;
  String? _loadError;
  List<AgentPreset> _presets = const [];

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
      final presets = await widget.client.listPresets();
      if (!mounted) return;
      setState(() {
        _presets = presets;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presets de agente'),
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
    if (_loading && _presets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Não foi possível carregar os presets.\n$_loadError',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _reload, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    if (_presets.isEmpty) {
      return const Center(child: Text('Nenhum preset no host.'));
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final p = _presets[i];
          final tags = [
            if (p.isDefault) 'padrão',
            if (p.isManager) 'gerente',
          ];
          return ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: Text(p.name),
            subtitle: Text([
              p.agentType,
              if (p.command != null) p.command!,
              ...tags,
            ].join(' · ')),
          );
        },
      ),
    );
  }
}
