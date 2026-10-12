import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/chat_mention.dart';

/// Seletor de `@` acima do campo: alvos do host (agentes, andares, notas, ações)
/// e arquivos do terminal. Pastas navegam; arquivos e alvos são inseridos no texto.
class MentionPicker extends StatelessWidget {
  final List<ChatMention> mentions;
  final List<ChatFileEntry> files;
  final bool loadingFiles;
  final String? filesError;
  final ValueChanged<ChatMention> onMention;
  final ValueChanged<ChatFileEntry> onFile;

  const MentionPicker({
    super.key,
    required this.mentions,
    required this.files,
    required this.onMention,
    required this.onFile,
    this.loadingFiles = false,
    this.filesError,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      for (final m in mentions)
        ListTile(
          dense: true,
          leading: const Icon(Icons.alternate_email_rounded, size: 16, color: AppColors.textAccent),
          title: Text(m.name, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          subtitle: m.floorName.isEmpty
              ? null
              : Text(m.floorName, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          onTap: () => onMention(m),
        ),
      for (final f in files)
        ListTile(
          dense: true,
          leading: Icon(
            f.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
            size: 16,
            color: AppColors.textSecondary,
          ),
          title: Text(f.relativePath,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis),
          onTap: () => onFile(f),
        ),
      if (loadingFiles)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      if (filesError != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(filesError!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ),
      if (mentions.isEmpty && files.isEmpty && !loadingFiles && filesError == null)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Nada encontrado', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ),
    ];
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: rows),
    );
  }
}
