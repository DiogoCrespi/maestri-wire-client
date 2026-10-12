import 'package:flutter/material.dart';
import '../../core/network/api_terminal_actions.dart';
import '../../core/network/wire_client.dart';
import '../../models/terminal_appearance.dart';
import '../../models/terminal_settings.dart';

/// Configurações de um terminal (GET/PUT `/api/terminals/{id}/settings`).
///
/// Abre a partir do sheet de ações: `Navigator.push(MaterialPageRoute(
/// builder: (_) => TerminalSettingsScreen(...)))`. Carrega sozinha o GET
/// (inclui `roles` e `themes`). Salvar faz um PUT de substituição completa.
///
/// [isRunning] vem de quem abre (o feed do workspace). Trocar a responsabilidade
/// de um terminal em execução reinicia o processo, e a tela pede confirmação.
/// Quem não é owner vê tudo somente leitura.
class TerminalSettingsScreen extends StatefulWidget {
  final WireClient client;
  final String workspaceId;
  final String terminalId;
  final String nodeId;
  final String title;
  final bool isOwner;
  final bool isRunning;

  const TerminalSettingsScreen({
    super.key,
    required this.client,
    required this.workspaceId,
    required this.terminalId,
    required this.nodeId,
    required this.title,
    required this.isOwner,
    this.isRunning = false,
  });

  @override
  State<TerminalSettingsScreen> createState() => _TerminalSettingsScreenState();
}

const _themeLabels = {
  'system': 'Do sistema',
  'dark': 'Escuro',
  'light': 'Claro',
  'custom': 'Tema específico',
};

const _chatFontLabels = {
  'system': 'Padrão',
  'monospaced': 'Monoespaçada',
  'rounded': 'Arredondada',
  'serif': 'Serifada',
};

const _chatTextSizeLabels = {
  'system': 'Padrão',
  'small': 'Pequeno',
  'medium': 'Médio',
  'large': 'Grande',
  'extraLarge': 'Muito grande',
  'extraExtraLarge': 'Enorme',
};

class _TerminalSettingsScreenState extends State<TerminalSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  TerminalSettings? _original;

  // Rascunho editado na tela.
  final _commandController = TextEditingController();
  final _iconController = TextEditingController();
  final _colorController = TextEditingController();
  String? _roleId;
  bool _maestroMode = false;
  bool _monitorActivity = false;
  TerminalAppearance? _appearance;

  @override
  void initState() {
    super.initState();
    _colorController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _commandController.dispose();
    _iconController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final s = await widget.client.getTerminalSettings(widget.terminalId);
      if (!mounted) return;
      _original = s;
      _commandController.text = s.command;
      _iconController.text = s.icon ?? '';
      _colorController.text = s.color ?? '';
      _roleId = s.roleId != null && s.roles.any((r) => r.id == s.roleId) ? s.roleId : null;
      _maestroMode = s.maestroMode;
      _monitorActivity = s.monitorActivity;
      _appearance = s.appearanceModel;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _errorText(e);
      });
    }
  }

  String _errorText(Object e) =>
      e is TerminalActionException ? e.message : e.toString().replaceAll('Exception: ', '');

  bool get _editable => widget.isOwner && !_saving && _original != null;

  String? get _colorError {
    final c = _colorController.text.trim();
    if (c.isEmpty || isHexColor(c)) return null;
    return 'Use a cor no formato #RRGGBB';
  }

  bool get _roleChanged => _original != null && _roleId != _original!.roleId;

  bool get _dirty {
    final o = _original;
    if (o == null) return false;
    return _commandController.text.trim() != o.command ||
        _roleChanged ||
        _maestroMode != o.maestroMode ||
        _monitorActivity != o.monitorActivity ||
        _iconController.text.trim() != (o.icon ?? '') ||
        _colorController.text.trim() != (o.color ?? '') ||
        (_appearance != null && _appearance!.toJson() != o.appearanceModel?.toJson());
  }

  Future<bool> _confirmRoleRestart() async {
    if (!_roleChanged || !widget.isRunning) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trocar a responsabilidade?'),
        content: const Text(
          'O terminal está em execução. Trocar a responsabilidade reinicia o processo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trocar e reiniciar')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    final o = _original;
    if (o == null || _colorError != null) return;
    if (!await _confirmRoleRestart()) return;
    final icon = _iconController.text.trim();
    final color = _colorController.text.trim();
    setState(() => _saving = true);
    try {
      await widget.client.putTerminalSettings(
        widget.terminalId,
        command: _commandController.text.trim(),
        maestroMode: _maestroMode,
        monitorActivity: _monitorActivity,
        icon: icon.isEmpty ? null : icon,
        clearIcon: icon.isEmpty,
        color: color.isEmpty ? null : color,
        clearColor: color.isEmpty,
        roleId: _roleId,
        clearRole: _roleId == null,
        appearance: _appearance,
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Configurações salvas.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Não foi possível salvar: ${_errorText(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Configurações · ${widget.title}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_loadError!, textAlign: TextAlign.center),
                      ),
                      FilledButton(onPressed: _load, child: const Text('Tentar de novo')),
                    ],
                  ),
                )
              : _body(theme),
      bottomNavigationBar: _loading || _loadError != null || !widget.isOwner
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton(
                  onPressed: _editable && _dirty && _colorError == null ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
                ),
              ),
            ),
    );
  }

  Widget _body(ThemeData theme) {
    final s = _original!;
    final appearance = _appearance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!widget.isOwner)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Só o dono do workspace pode alterar este terminal.'),
          ),
        if (s.workingDirectory.isNotEmpty) ...[
          Text('Diretório', style: theme.textTheme.labelMedium),
          SelectableText(s.workingDirectory, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _commandController,
          enabled: _editable,
          decoration: const InputDecoration(
            labelText: 'Comando',
            hintText: 'Vazio roda só o shell',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          key: ValueKey('role-$_roleId'),
          initialValue: _roleId,
          decoration: const InputDecoration(
            labelText: 'Responsabilidade',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Nenhuma')),
            for (final r in s.roles)
              DropdownMenuItem<String?>(value: r.id, child: Text(r.name)),
          ],
          onChanged: _editable ? (v) => setState(() => _roleId = v) : null,
        ),
        if (_roleChanged && widget.isRunning)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Atenção: o terminal está em execução. Salvar reinicia o processo.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Modo Maestro'),
          subtitle: const Text('Muda o que o agente pode fazer no canvas'),
          value: _maestroMode,
          onChanged: _editable ? (v) => setState(() => _maestroMode = v) : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Monitorar atividade'),
          value: _monitorActivity,
          onChanged: _editable ? (v) => setState(() => _monitorActivity = v) : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _iconController,
                enabled: _editable,
                decoration: const InputDecoration(
                  labelText: 'Ícone',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _colorController,
                enabled: _editable,
                decoration: InputDecoration(
                  labelText: 'Cor',
                  hintText: '#RRGGBB',
                  errorText: _colorError,
                  border: const OutlineInputBorder(),
                  suffixIcon: _colorSwatch(_colorController.text.trim()),
                ),
              ),
            ),
          ],
        ),
        if (appearance != null) ...[
          const SizedBox(height: 24),
          Text('Aparência', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _appearanceSection(appearance, s.themes),
        ],
      ],
    );
  }

  Widget? _colorSwatch(String value) {
    final argb = hexColorToArgb(value);
    if (argb == null) return null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: CircleAvatar(radius: 8, backgroundColor: Color(argb)),
    );
  }

  Widget _appearanceSection(TerminalAppearance a, List<ThemeOption> themes) {
    final themeValue = kAppearanceThemes.contains(a.theme) ? a.theme : 'system';
    final customValid = themes.any((t) => t.id == a.customThemeId);
    final size = a.terminalFontSize;
    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('theme-$themeValue'),
          initialValue: themeValue,
          decoration: const InputDecoration(labelText: 'Tema', border: OutlineInputBorder()),
          items: [
            for (final t in kAppearanceThemes)
              DropdownMenuItem(value: t, child: Text(_themeLabels[t] ?? t)),
          ],
          onChanged: _editable
              ? (v) => setState(() => _appearance = a.copyWith(
                    theme: v,
                    clearCustomThemeId: v != 'custom',
                    customThemeId: v == 'custom' && !customValid && themes.isNotEmpty
                        ? themes.first.id
                        : null,
                  ))
              : null,
        ),
        if (themeValue == 'custom') ...[
          const SizedBox(height: 12),
          if (themes.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('O host não listou temas.'),
            )
          else
            DropdownButtonFormField<String>(
              key: ValueKey('custom-${a.customThemeId}'),
              initialValue: customValid ? a.customThemeId : null,
              decoration: const InputDecoration(
                labelText: 'Tema específico',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in themes)
                  DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
              onChanged: _editable
                  ? (v) => setState(() => _appearance = a.copyWith(customThemeId: v))
                  : null,
            ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tamanho automático da fonte do terminal'),
          value: size == null,
          onChanged: _editable
              ? (auto) => setState(() => _appearance = auto
                  ? a.copyWith(clearTerminalFontSize: true)
                  : a.copyWith(terminalFontSize: 13))
              : null,
        ),
        if (size != null)
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: size.toDouble().clamp(
                        kTerminalFontSizeMin.toDouble(),
                        kTerminalFontSizeMax.toDouble(),
                      ),
                  min: kTerminalFontSizeMin.toDouble(),
                  max: kTerminalFontSizeMax.toDouble(),
                  divisions: kTerminalFontSizeMax - kTerminalFontSizeMin,
                  label: '$size',
                  onChanged: _editable
                      ? (v) => setState(() => _appearance = a.copyWith(terminalFontSize: v.round()))
                      : null,
                ),
              ),
              SizedBox(width: 40, child: Text('$size pt')),
            ],
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('chatFont-${a.chatFont}'),
          initialValue: kChatFonts.contains(a.chatFont) ? a.chatFont : 'system',
          decoration: const InputDecoration(labelText: 'Fonte do chat', border: OutlineInputBorder()),
          items: [
            for (final f in kChatFonts)
              DropdownMenuItem(value: f, child: Text(_chatFontLabels[f] ?? f)),
          ],
          onChanged: _editable
              ? (v) => setState(() => _appearance = a.copyWith(chatFont: v))
              : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('chatSize-${a.chatTextSize}'),
          initialValue: kChatTextSizes.contains(a.chatTextSize) ? a.chatTextSize : 'system',
          decoration: const InputDecoration(
            labelText: 'Tamanho do texto do chat',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final z in kChatTextSizes)
              DropdownMenuItem(value: z, child: Text(_chatTextSizeLabels[z] ?? z)),
          ],
          onChanged: _editable
              ? (v) => setState(() => _appearance = a.copyWith(chatTextSize: v))
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Começar no chat'),
          subtitle: const Text('Ao abrir o terminal, mostra a face de chat'),
          value: a.startInChatMode,
          onChanged: _editable
              ? (v) => setState(() => _appearance = a.copyWith(startInChatMode: v))
              : null,
        ),
      ],
    );
  }
}
