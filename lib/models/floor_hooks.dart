import 'package:uuid/uuid.dart';

/// Hooks de andar (`hooks` de GET/PUT …/hooks): comandos de setup, run e teardown.
/// Contrato: notes/maestri-wire.md, "Hooks de andar" (capability floorHooks).

/// Seções de hooks, na ordem em que o host as mostra.
const hookSections = ['setup', 'run', 'teardown'];

String hookSectionLabel(String section) {
  switch (section) {
    case 'setup':
      return 'Setup';
    case 'run':
      return 'Run';
    case 'teardown':
      return 'Teardown';
    default:
      return section;
  }
}

class HookCommand {
  final String id;
  final String command;
  final bool isEnabled;

  const HookCommand({required this.id, required this.command, this.isEnabled = true});

  /// Id novo para um comando criado no cliente. Comandos existentes mantêm o id.
  static String newId() => const Uuid().v4();

  HookCommand copyWith({String? command, bool? isEnabled}) => HookCommand(
        id: id,
        command: command ?? this.command,
        isEnabled: isEnabled ?? this.isEnabled,
      );

  static HookCommand? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final command = raw['command'];
    if (id is! String || id.isEmpty || command is! String) return null;
    return HookCommand(id: id, command: command, isEnabled: raw['isEnabled'] != false);
  }

  Map<String, dynamic> toJson() => {'id': id, 'command': command, 'isEnabled': isEnabled};
}

class FloorHooks {
  final bool isEnabled;
  final bool autoRunSetup;
  final List<HookCommand> setup;
  final List<HookCommand> run;
  final List<HookCommand> teardown;

  const FloorHooks({
    this.isEnabled = false,
    this.autoRunSetup = true,
    this.setup = const [],
    this.run = const [],
    this.teardown = const [],
  });

  static const empty = FloorHooks();

  List<HookCommand> section(String name) {
    switch (name) {
      case 'setup':
        return setup;
      case 'run':
        return run;
      case 'teardown':
        return teardown;
    }
    return const [];
  }

  FloorHooks withSection(String name, List<HookCommand> commands) => FloorHooks(
        isEnabled: isEnabled,
        autoRunSetup: autoRunSetup,
        setup: name == 'setup' ? commands : setup,
        run: name == 'run' ? commands : run,
        teardown: name == 'teardown' ? commands : teardown,
      );

  FloorHooks copyWith({bool? isEnabled, bool? autoRunSetup}) => FloorHooks(
        isEnabled: isEnabled ?? this.isEnabled,
        autoRunSetup: autoRunSetup ?? this.autoRunSetup,
        setup: setup,
        run: run,
        teardown: teardown,
      );

  static List<HookCommand> _commands(Object? raw) => raw is List
      ? [for (final c in raw) if (HookCommand.tryFromJson(c) case final HookCommand cmd) cmd]
      : const [];

  factory FloorHooks.fromJson(Object? raw) {
    if (raw is! Map) return empty;
    return FloorHooks(
      isEnabled: raw['isEnabled'] == true,
      autoRunSetup: raw['autoRunSetup'] != false,
      setup: _commands(raw['setup']),
      run: _commands(raw['run']),
      teardown: _commands(raw['teardown']),
    );
  }

  /// Formato do PUT: substitui os hooks inteiros.
  Map<String, dynamic> toJson() => {
        'isEnabled': isEnabled,
        'autoRunSetup': autoRunSetup,
        'setup': [for (final c in setup) c.toJson()],
        'run': [for (final c in run) c.toJson()],
        'teardown': [for (final c in teardown) c.toJson()],
      };
}

/// Execução que o host ainda lembra (`runs`).
class HookRun {
  final String commandId;
  final String? floorId;
  final bool isRunning;
  final int? exitCode;
  final String? finishedAt;

  const HookRun({
    required this.commandId,
    this.floorId,
    this.isRunning = false,
    this.exitCode,
    this.finishedAt,
  });

  static HookRun? tryFromJson(Object? raw) {
    if (raw is! Map || raw['commandId'] is! String) return null;
    final exit = raw['exitCode'];
    return HookRun(
      commandId: raw['commandId'] as String,
      floorId: raw['floorId'] is String ? raw['floorId'] as String : null,
      isRunning: raw['isRunning'] == true,
      exitCode: exit is int ? exit : null,
      finishedAt: raw['finishedAt'] is String ? raw['finishedAt'] as String : null,
    );
  }
}

class FloorHooksSnapshot {
  final FloorHooks hooks;
  final List<HookRun> runs;

  const FloorHooksSnapshot({required this.hooks, this.runs = const []});

  factory FloorHooksSnapshot.fromJson(Map<String, dynamic> json) => FloorHooksSnapshot(
        hooks: FloorHooks.fromJson(json['hooks']),
        runs: json['runs'] is List
            ? [for (final r in json['runs'] as List) if (HookRun.tryFromJson(r) case final HookRun run) run]
            : const [],
      );

  /// Execução mais recente de um comando, se houver.
  HookRun? runFor(String commandId) {
    for (final r in runs.reversed) {
      if (r.commandId == commandId) return r;
    }
    return null;
  }
}
