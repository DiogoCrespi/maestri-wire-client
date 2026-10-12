import 'dart:convert';

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/api_files.dart';
import '../../core/network/wire_client.dart';

/// Visualizador de um nó de arquivo do canvas.
/// - imagem: `…/file/preview` (reduzida pelo host), com zoom;
/// - texto (md, txt, json, log, csv…): os primeiros [kTextPreviewBytes] bytes via `Range`;
/// - outros: informa que o arquivo fica no host.
class FileViewerScreen extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final String nodeId;
  final String displayName;
  final bool isImage;
  final bool isVideo;

  const FileViewerScreen({
    super.key,
    required this.client,
    required this.workspaceId,
    required this.nodeId,
    required this.displayName,
    this.isImage = false,
    this.isVideo = false,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

/// Quanto de um arquivo de texto é lido para a visualização.
const int kTextPreviewBytes = 256 * 1024;

const List<String> _textExtensions = [
  '.md', '.txt', '.json', '.log', '.csv', '.yaml', '.yml', '.xml', '.dart', '.swift',
  '.js', '.ts', '.py', '.sh', '.html', '.css',
];

/// Decide se um nome de arquivo deve ser lido como texto.
bool isTextFileName(String name) {
  final lower = name.toLowerCase();
  return _textExtensions.any(lower.endsWith);
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  bool _loading = true;
  String? _error;
  String? _text;
  bool _truncated = false;
  NodeFileBytes? _image;
  int? _total;

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
      if (widget.isImage) {
        final preview = await loadNodePreview(
          client: widget.client,
          workspaceId: widget.workspaceId,
          nodeId: widget.nodeId,
        );
        if (!mounted) return;
        if (preview.statusCode != 200) {
          throw Exception('o host não tem uma prévia desta imagem (${preview.statusCode})');
        }
        setState(() {
          _image = preview;
          _loading = false;
        });
        return;
      }
      if (!widget.isVideo && isTextFileName(widget.displayName)) {
        final chunk = await loadNodeFile(
          client: widget.client,
          workspaceId: widget.workspaceId,
          nodeId: widget.nodeId,
          rangeStart: 0,
          rangeEnd: kTextPreviewBytes - 1,
        );
        if (!mounted) return;
        if (chunk.statusCode != 200 && chunk.statusCode != 206) {
          throw Exception('o host respondeu ${chunk.statusCode}');
        }
        final total = chunk.totalLength ?? chunk.bytes.length;
        setState(() {
          _text = utf8.decode(chunk.bytes, allowMalformed: true);
          _truncated = total > chunk.bytes.length;
          _total = total;
          _loading = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível abrir o arquivo: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(widget.displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _message(_error!)
              : _image != null
                  ? InteractiveViewer(
                      maxScale: 6,
                      child: Center(
                        child: Image.memory(
                          _image!.bytes,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => _message('Imagem não pôde ser decodificada.'),
                        ),
                      ),
                    )
                  : _text != null
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                _text!,
                                style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary),
                              ),
                              if (_truncated)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Mostrando os primeiros ${kTextPreviewBytes ~/ 1024} KB de ${_total ?? '?'} bytes.',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : _message(widget.isVideo
                          ? 'Vídeo: a reprodução acontece no host.'
                          : 'Este tipo de arquivo não tem visualização no celular.'),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        ),
      );
}
