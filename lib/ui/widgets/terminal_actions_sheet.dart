import 'package:flutter/material.dart';
import '../../core/network/api_terminal_actions.dart';
import '../../core/network/wire_client.dart';
import '../../models/terminal_settings.dart';
import '../screens/terminal_settings_screen.dart';

/// Outro nó do andar que pode receber uma corda a partir deste terminal.
typedef TerminalPeer = ({String nodeId, String title});

/// Ações de um terminal existente: Maestro, começar no chat, focar, reiniciar,
/// descarregar, conectar, desconectar, encerrar, excluir e configurações
/// (tela [TerminalSettingsScreen]). Ações destrutivas pedem confirmação.
/// Todas são escrita: só o owner do workspace pode executá-las.
Future<void> showTerminalActionsSheet(
  BuildContext context, {
  required WireClient client,
  required String workspaceId,
  required String terminalId,
  required String nodeId,
  required String title,
  required bool maestroMode,
  required bool isOwner,
  required List<TerminalPeer> otherNodes,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _TerminalActionsSheet(
      client: client,
      workspaceId: workspaceId,
      terminalId: terminalId,
      nodeId: nodeId,
      title: title,
      initialMaestroMode: maestroMode,
      isOwner: isOwner,
      otherNodes: otherNodes,
      onChanged: onChanged,
    ),
  );
}

/// Corda já existente que sai ou chega a este nó. Guarda a direção real
/// (from/to) para o DELETE.
typedef _Link = ({String fromNodeId, String toNodeId, String otherNodeId, String otherTitle});

class _TerminalActionsSheet extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final String terminalId;
  final String nodeId;
  final String title;
  final bool initialMaestroMode;
  final bool isOwner;
  final List<TerminalPeer> otherNodes;
  final VoidCallback? onChanged;

  const _TerminalActionsSheet({
    required this.client,
    required this.workspaceId,
    required this.terminalId,
    required this.nodeId,
    required this.title,
    required this.initialMaestroMode,
    required this.isOwner,
    required this.otherNodes,
    this.onChanged,
  });

  @override
  State<_TerminalActionsSheet> createState() => _TerminalActionsSheetState();
}

class _TerminalActionsSheetState extends State<_TerminalActionsSheet> {
  late bool _maestro = widget.initialMaestroMode;
  bool _running = false;
  bool _loaded = false;
  bool _busy = false;
  List<_Link> _links = const [];
  TerminalSettings? _settings;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  /// Lê do feed do workspace: se o processo está rodando e as cordas do nó.
  Future<void> _loadState() async {
    try {
      final settings = await _tryLoadSettings();
      final feed = await widget.client.getWorkspaceFeed(widget.workspaceId);
      final items = feed['items'] is List ? feed['items'] as List : const [];
      var running = false;
      for (final it in items) {
        if (it is! Map || it['kind'] != 'terminal') continue;
        final t = it['terminal'];
        if (t is Map && t['id'] == widget.terminalId) {
          running = t['isRunning'] == true;
        }
      }

      final canvas = feed['canvas'] is Map ? feed['canvas'] as Map : const {};
      final kinds = <String, String>{};
      final titles = <String, String>{
        for (final p in widget.otherNodes) p.nodeId: p.title,
      };
      for (final n in (canvas['nodes'] is List ? canvas['nodes'] as List : const [])) {
        if (n is! Map || n['id'] is! String) continue;
        kinds[n['id'] as String] = '${n['kind']}';
        if (n['title'] is String) titles[n['id'] as String] = n['title'] as String;
      }

      final links = <_Link>[];
      final conns = canvas['connections'] is List ? canvas['connections'] as List : const [];
      for (final c in conns) {
        if (c is! Map) continue;
        final from = c['fromNodeId'];
        final to = c['toNodeId'];
        if (from is! String || to is! String) continue;
        final String other;
        if (from == widget.nodeId) {
          other = to;
        } else if (to == widget.nodeId) {
          other = from;
        } else {
          continue;
        }
        // O host recusa DELETE em conector (400): esse caso não entra na lista.
        if (kinds[other] == 'connector') continue;
        links.add((
          fromNodeId: from,
          toNodeId: to,
          otherNodeId: other,
          otherTitle: titles[other] ?? other,
        ));
      }

      if (!mounted) return;
      setState(() {
        _running = running;
        _links = links;
        if (settings != null) _settings = settings;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  /// Configurações do terminal; null se o host não responde (a seção some).
  Future<TerminalSettings?> _tryLoadSettings() async {
    try {
      return await widget.client.getTerminalSettings(widget.terminalId);
    } catch (_) {
      return null;
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  String _errorText(Object e) =>
      e is TerminalActionException ? e.message : e.toString().replaceAll('Exception: ', '');

  /// Executa uma ação: trava os botões, mostra erro, e depois recarrega o estado.
  Future<bool> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    var ok = false;
    try {
      await action();
      ok = true;
    } catch (e) {
      _snack(_errorText(e));
    }
    if (!mounted) return ok;
    setState(() => _busy = false);
    if (ok) widget.onChanged?.call();
    await _loadState();
    return ok;
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _toggleMaestro(bool value) async {
    final ok = await _confirm(
      title: value ? 'Ligar modo Maestro?' : 'Desligar modo Maestro?',
      body: value
          ? 'Isto muda o que o agente pode fazer no canvas: passa a poder coordenar outros terminais.'
          : 'Isto muda o que o agente pode fazer no canvas: perde as permissões de Maestro.',
      action: value ? 'Ligar' : 'Desligar',
    );
    if (!ok) return;
    final done = await _run(() => widget.client.putTerminalSettings(
          widget.terminalId,
          maestroMode: value,
        ));
    if (done && mounted) setState(() => _maestro = value);
  }

  /// Descarregar: desmonta a sessão até o terminal ser reiniciado. O scrollback
  /// fica preservado.
  Future<void> _unload() async {
    final ok = await _confirm(
      title: 'Descarregar "${widget.title}"?',
      body: _running
          ? 'O processo será desmontado da tela e o terminal ficará dormente. '
              'O histórico (scrollback) é preservado, e o terminal volta com Reiniciar.'
          : 'O terminal ficará dormente. O histórico (scrollback) é preservado, '
              'e volta com Reiniciar.',
      action: 'Descarregar',
    );
    if (!ok) return;
    await _run(() => widget.client.unloadTerminal(widget.terminalId));
  }

  /// Começar no chat: lê a aparência atual e troca só `startInChatMode`.
  Future<void> _toggleStartInChat(bool value) async {
    final current = _settings?.appearanceModel;
    if (current == null) return;
    await _run(() => widget.client.putTerminalSettings(
          widget.terminalId,
          appearance: current.copyWith(startInChatMode: value),
        ));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalSettingsScreen(
          client: widget.client,
          workspaceId: widget.workspaceId,
          terminalId: widget.terminalId,
          nodeId: widget.nodeId,
          title: widget.title,
          isOwner: widget.isOwner,
          isRunning: _running,
        ),
      ),
    );
    if (!mounted) return;
    widget.onChanged?.call();
    await _loadState();
  }

  Future<void> _kill() async {
    final ok = await _confirm(
      title: 'Encerrar processo?',
      body: 'O processo de "${widget.title}" será encerrado. O terminal continua no canvas.',
      action: 'Encerrar',
      destructive: true,
    );
    if (!ok) return;
    await _run(() => widget.client.killTerminal(widget.terminalId));
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      title: 'Excluir terminal?',
      body: _running
          ? '"${widget.title}" está rodando: o processo será encerrado e o nó removido do canvas.'
          : '"${widget.title}" será removido do canvas.',
      action: 'Excluir',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final deleted = await _run(() async {
      if (_running) await widget.client.killTerminal(widget.terminalId);
      final removed = await widget.client.deleteNode(
        workspaceId: widget.workspaceId,
        nodeId: widget.nodeId,
      );
      if (!removed) throw Exception('O host não removeu o nó');
    });
    if (deleted && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _connect(TerminalPeer peer) async {
    await _run(() => widget.client.connectNodes(widget.workspaceId, widget.nodeId, peer.nodeId));
  }

  Future<void> _disconnect(_Link link) async {
    await _run(() => widget.client.disconnectNodes(
          widget.workspaceId,
          link.fromNodeId,
          link.toNodeId,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.isOwner && !_busy;
    final connected = _links.map((l) => l.otherNodeId).toSet();
    final connectable = widget.otherNodes.where((p) => !connected.contains(p.nodeId)).toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (!widget.isOwner)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Só o dono do workspace pode alterar este terminal.'),
              ),
            SwitchListTile(
              title: const Text('Modo Maestro'),
              subtitle: const Text('Muda o que o agente pode fazer no canvas'),
              value: _maestro,
              onChanged: enabled ? _toggleMaestro : null,
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Focar no host'),
              onTap: enabled ? () => _run(() => widget.client.focusTerminal(widget.terminalId)) : null,
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reiniciar'),
              onTap: enabled ? () => _run(() => widget.client.restartTerminal(widget.terminalId)) : null,
            ),
            ListTile(
              leading: const Icon(Icons.unarchive_outlined),
              title: const Text('Descarregar'),
              subtitle: const Text('Desmonta a sessão; o histórico fica. Reiniciar volta.'),
              onTap: enabled ? _unload : null,
            ),
            if (_settings?.appearanceModel != null)
              SwitchListTile(
                secondary: const Icon(Icons.chat_outlined),
                title: const Text('Começar no chat'),
                subtitle: const Text('Ao abrir, mostra a face de chat'),
                value: _settings!.appearanceModel!.startInChatMode,
                onChanged: enabled ? _toggleStartInChat : null,
              ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Configurações'),
              subtitle: const Text('Comando, responsabilidade, Maestro, ícone, cor, aparência'),
              onTap: enabled ? _openSettings : null,
            ),
            ExpansionTile(
              leading: const Icon(Icons.add_link),
              title: const Text('Conectar a…'),
              enabled: enabled,
              children: [
                if (connectable.isEmpty)
                  const ListTile(
                    dense: true,
                    title: Text('Nenhum outro nó disponível no andar'),
                  ),
                for (final p in connectable)
                  ListTile(
                    dense: true,
                    title: Text(p.title),
                    onTap: enabled ? () => _connect(p) : null,
                  ),
              ],
            ),
            ExpansionTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Desconectar de…'),
              enabled: enabled && _loaded,
              children: [
                if (_loaded && _links.isEmpty)
                  const ListTile(dense: true, title: Text('Nenhuma corda neste nó')),
                for (final l in _links)
                  ListTile(
                    dense: true,
                    title: Text(l.otherTitle),
                    onTap: enabled ? () => _disconnect(l) : null,
                  ),
              ],
            ),
            ListTile(
              leading: const Icon(Icons.stop_circle_outlined),
              title: const Text('Encerrar processo'),
              enabled: enabled && _running,
              onTap: enabled && _running ? _kill : null,
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text(
                'Excluir terminal',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              enabled: enabled,
              onTap: enabled ? _delete : null,
            ),
          ],
        ),
      ),
    );
  }
}
