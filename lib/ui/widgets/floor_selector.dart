import 'package:flutter/material.dart';
import '../../core/network/api_floors.dart';
import '../../models/floor.dart';

/// Seletor de andares: lista os andares do workspace, com atenção, andar
/// ativo no host e status/PR. Mostrar um andar troca só o que o cliente exibe;
/// ativar é escrita no host e só ocorre pelo botão "Ativar".
///
/// Uso:
/// ```dart
/// FloorSelector.show(
///   context,
///   floors: floors,                    // de FloorsApi.getFloors ou do feed
///   viewingFloor: currentFloor?.queryValue, // null = o andar ativo do host
///   onView: (f) => controller.switchFloor(f),
///   onActivate: (f) => client.activateFloor(workspaceId, f), // null esconde
/// );
/// ```
class FloorSelector extends StatefulWidget {
  final List<FloorMeta> floors;

  /// `queryValue` do andar exibido no canvas. Null significa o andar ativo do host.
  final String? viewingFloor;

  /// Mostrar outro andar no cliente (não move o host).
  final ValueChanged<FloorMeta> onView;

  /// Ativa o andar no host. Null esconde o botão "Ativar".
  final Future<void> Function(FloorMeta floor)? onActivate;

  /// Novo andar (botão no topo). Null esconde o botão.
  final VoidCallback? onCreate;

  /// Gerenciar um andar (toque longo): renomear, descarregar, aterrissar, excluir.
  final ValueChanged<FloorMeta>? onManage;

  const FloorSelector({
    super.key,
    required this.floors,
    required this.onView,
    this.viewingFloor,
    this.onActivate,
    this.onCreate,
    this.onManage,
  });

  /// Abre o seletor num bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required List<FloorMeta> floors,
    required ValueChanged<FloorMeta> onView,
    String? viewingFloor,
    Future<void> Function(FloorMeta floor)? onActivate,
    VoidCallback? onCreate,
    ValueChanged<FloorMeta>? onManage,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: FloorSelector(
            floors: floors,
            viewingFloor: viewingFloor,
            onView: (f) {
              Navigator.of(sheetContext).pop();
              onView(f);
            },
            onActivate: onActivate,
            onCreate: onCreate == null
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    onCreate();
                  },
            onManage: onManage == null
                ? null
                : (f) {
                    Navigator.of(sheetContext).pop();
                    onManage(f);
                  },
          ),
        ),
      ),
    );
  }

  @override
  State<FloorSelector> createState() => _FloorSelectorState();
}

class _FloorSelectorState extends State<FloorSelector> {
  String? _busyKey;

  bool _isViewing(FloorMeta f) => widget.viewingFloor == null
      ? f.isActive
      : widget.viewingFloor == f.queryValue;

  Future<void> _activate(FloorMeta f) async {
    final activate = widget.onActivate;
    if (activate == null || _busyKey != null) return;
    setState(() => _busyKey = f.queryValue);
    try {
      await activate(f);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text('Não foi possível ativar "${f.name}": ${hostErrorText(e)}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final floors = FloorMeta.displayOrder(widget.floors);
    final theme = Theme.of(context);

    if (floors.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Nenhum andar.', style: theme.textTheme.bodyMedium),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(child: Text('Andares', style: theme.textTheme.titleMedium)),
                if (widget.onCreate != null)
                  TextButton.icon(
                    onPressed: widget.onCreate,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Novo'),
                  ),
              ],
            ),
          ),
          for (final f in floors)
            _FloorTile(
              floor: f,
              isViewing: _isViewing(f),
              isBusy: _busyKey == f.queryValue,
              canActivate: widget.onActivate != null && !f.isActive,
              onView: () => widget.onView(f),
              onActivate: () => _activate(f),
              onManage: widget.onManage == null ? null : () => widget.onManage!(f),
            ),
        ],
      ),
    );
  }
}

class _FloorTile extends StatelessWidget {
  final FloorMeta floor;
  final bool isViewing;
  final bool isBusy;
  final bool canActivate;
  final VoidCallback onView;
  final VoidCallback onActivate;
  final VoidCallback? onManage;

  const _FloorTile({
    required this.floor,
    required this.isViewing,
    required this.isBusy,
    required this.canActivate,
    required this.onView,
    required this.onActivate,
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = floor;
    final hasAttention = f.attentionCount > 0;

    return ListTile(
      selected: isViewing,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      leading: Icon(f.isGround ? Icons.landscape_outlined : Icons.layers_outlined),
      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (f.isActive)
            Text('No host agora', style: theme.textTheme.bodySmall)
          else if (f.isDormant)
            Text('Em espera', style: theme.textTheme.bodySmall),
          if (f.status != null) FloorStatusLine(status: f.status!),
          if (f.pullRequest != null) FloorPullRequestLine(pr: f.pullRequest!),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAttention)
            Semantics(
              label: '${f.attentionCount} em atenção',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${f.attentionCount}',
                  style: TextStyle(
                    color: theme.colorScheme.onError,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (canActivate) ...[
            const SizedBox(width: 8),
            isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(onPressed: onActivate, child: const Text('Ativar')),
          ],
        ],
      ),
      onTap: onView,
      onLongPress: onManage,
    );
  }
}

/// Estado e texto do relato do andar, com progresso quando houver.
class FloorStatusLine extends StatelessWidget {
  final FloorStatus status;

  const FloorStatusLine({super.key, required this.status});

  static String stateLabel(String state) {
    switch (state) {
      case FloorStatus.working:
        return 'Trabalhando';
      case FloorStatus.blocked:
        return 'Bloqueado';
      case FloorStatus.review:
        return 'Revisão';
      case FloorStatus.done:
        return 'Concluído';
      default:
        return 'Aguardando';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (status.state) {
      FloorStatus.working => scheme.primary,
      FloorStatus.blocked => scheme.error,
      FloorStatus.review => scheme.tertiary,
      FloorStatus.done => scheme.secondary,
      _ => scheme.outline,
    };
    final author = status.author == null ? '' : ' · ${status.author}';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: stateLabel(status.state),
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ': ${status.text}$author'),
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
          if (status.progress != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: status.progress, color: color),
          ],
        ],
      ),
    );
  }
}

/// Linha do pull request ligado ao andar.
class FloorPullRequestLine extends StatelessWidget {
  final FloorPullRequest pr;

  const FloorPullRequestLine({super.key, required this.pr});

  static String attentionLabel(String? attention) {
    switch (attention) {
      case 'conflicts':
        return 'conflitos';
      case 'checksFailing':
        return 'checks falhando';
      case 'changesRequested':
        return 'mudanças pedidas';
      case 'approved':
        return 'aprovado';
      case 'checksRunning':
        return 'checks rodando';
      default:
        return ''; // desconhecido: não desenhar nada
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[
      if (pr.number != null) '#${pr.number}',
      if (pr.title != null) pr.title!,
      if (pr.state == 'merged') 'mesclado',
      if (pr.state == 'closed') 'fechado',
      if (pr.isDraft) 'rascunho',
      if (pr.isReview) 'revisão',
      if (pr.isReadOnly) 'somente leitura',
      if (attentionLabel(pr.attention).isNotEmpty) attentionLabel(pr.attention),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'PR ${parts.join(' · ')}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: pr.attention == 'conflicts' || pr.attention == 'checksFailing'
              ? theme.colorScheme.error
              : null,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
