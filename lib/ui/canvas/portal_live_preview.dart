import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../core/network/wire_client.dart';

/// Prévia ao vivo da página de um portal: GET /api/portals/{id}/snapshot.
///
/// O host renderiza a imagem a cada requisição. Com o ETag, uma imagem inalterada
/// custa um 304 sem corpo. Quando o host não está renderizando (503/404), mostra
/// [fallback]. O polling só roda enquanto o card está montado.
class PortalLivePreview extends StatefulWidget {
  final WireClient client;
  final String portalId;
  final Widget fallback;
  final Duration interval;

  const PortalLivePreview({
    Key? key,
    required this.client,
    required this.portalId,
    required this.fallback,
    this.interval = const Duration(seconds: 5),
  }) : super(key: key);

  @override
  State<PortalLivePreview> createState() => _PortalLivePreviewState();
}

class _PortalLivePreviewState extends State<PortalLivePreview> {
  Timer? _timer;
  bool _inFlight = false;
  String? _etag;
  Uint8List? _image;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.interval, (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant PortalLivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.portalId != widget.portalId) {
      _etag = null;
      _image = null;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_inFlight || !mounted) return;
    _inFlight = true;
    try {
      final snap = await widget.client.getPortalSnapshot(widget.portalId, etag: _etag);
      if (!mounted) return;
      if (snap != null) {
        setState(() {
          _image = Uint8List.fromList(snap.bytes);
          _etag = snap.etag;
        });
      } else if (_image != null && _etag == null) {
        // sem ETag do host: não mantém imagem antiga como se fosse atual
        setState(() => _image = null);
      }
    } catch (_) {
      // Host ocupado ou sem rede: mantém a última imagem até a próxima tentativa
    } finally {
      _inFlight = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return widget.fallback;
    return Image.memory(
      image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}
