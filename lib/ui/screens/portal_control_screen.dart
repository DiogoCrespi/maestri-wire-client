import 'package:flutter/material.dart';
import '../../core/network/api_portals.dart';
import '../../core/network/wire_client.dart';
import '../canvas/portal_live_preview.dart';

/// Controle de um portal: prévia ao vivo, recarregar, voltar, avançar,
/// navegar para uma URL e descarregar.
///
/// Abra com `PortalControlScreen(client: client, portalId: id, portalName: name)`
/// (uma tela cheia ou dentro de um bottom sheet). A prévia abre em tela cheia
/// ao tocar nela. Descarregar pede confirmação.
class PortalControlScreen extends StatefulWidget {
  final WireClient client;
  final String portalId;
  final String? portalName;

  const PortalControlScreen({
    super.key,
    required this.client,
    required this.portalId,
    this.portalName,
  });

  @override
  State<PortalControlScreen> createState() => _PortalControlScreenState();
}

class _PortalControlScreenState extends State<PortalControlScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String get _title => widget.portalName?.trim().isNotEmpty == true
      ? widget.portalName!.trim()
      : 'Portal';

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Executa uma ação de escrita com indicador de ocupado e feedback.
  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _snack('$label: feito.');
    } catch (e) {
      _snack('$label falhou: ${_describe(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(Object e) =>
      e is ArgumentError ? '${e.message}' : e.toString();

  Future<void> _navigate() async {
    final String url;
    try {
      url = validatePortalUrl(_urlController.text);
    } catch (e) {
      _snack(_describe(e));
      return;
    }
    await _run(
        'Navegar', () => widget.client.navigatePortal(widget.portalId, url));
  }

  Future<void> _unload() async {
    final ok = await _confirm(
      title: 'Descarregar portal?',
      message: 'A página de "$_title" será descarregada no host. '
          'Use Recarregar para carregá-la de novo.',
      confirmLabel: 'Descarregar',
    );
    if (!ok) return;
    await _run(
        'Descarregar', () => widget.client.unloadPortal(widget.portalId));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
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
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel)),
        ],
      ),
    );
    return result == true;
  }

  void _openFullscreenPreview() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PortalPreviewFullscreen(
          client: widget.client, portalId: widget.portalId, title: _title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: _openFullscreenPreview,
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PortalLivePreview(
                  client: widget.client,
                  portalId: widget.portalId,
                  fallback: Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Text('Sem imagem ao vivo'),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('Toque na prévia para ver em tela cheia.',
              style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run('Recarregar',
                        () => widget.client.reloadPortal(widget.portalId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Recarregar'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run('Voltar',
                        () => widget.client.portalBack(widget.portalId)),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Voltar'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run('Avançar',
                        () => widget.client.portalForward(widget.portalId)),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Avançar'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _unload,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Descarregar'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Navegar para', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'https://exemplo.com',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _busy ? null : _navigate(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _navigate,
              child: const Text('Navegar'),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

/// Prévia ao vivo em tela cheia. Usa o mesmo polling com ETag da prévia de card.
class PortalPreviewFullscreen extends StatelessWidget {
  final WireClient client;
  final String portalId;
  final String title;

  const PortalPreviewFullscreen({
    super.key,
    required this.client,
    required this.portalId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: PortalLivePreview(
              client: client,
              portalId: portalId,
              interval: const Duration(seconds: 2),
              fallback: const Text('Sem imagem ao vivo',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}
