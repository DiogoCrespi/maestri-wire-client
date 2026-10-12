// Modelos das rotinas do host (capability `routines`).
// Contrato: notes/maestri-wire.md, seção "Rotinas".

/// Agendamento: `once`, `interval`, `daily` ou `weekly`. Outros valores vindos do host
/// são preservados em [kind] e tratados como "algum outro tipo".
class RoutineSchedule {
  final String kind;
  final DateTime? at; // once
  final int? seconds; // interval
  final int? hour; // daily, weekly
  final int? minute; // daily, weekly
  final List<int> weekdays; // weekly: 1…7, domingo é 1

  const RoutineSchedule({
    required this.kind,
    this.at,
    this.seconds,
    this.hour,
    this.minute,
    this.weekdays = const [],
  });

  const RoutineSchedule.once(DateTime when)
      : kind = 'once',
        at = when,
        seconds = null,
        hour = null,
        minute = null,
        weekdays = const [];

  const RoutineSchedule.interval(int secs)
      : kind = 'interval',
        at = null,
        seconds = secs,
        hour = null,
        minute = null,
        weekdays = const [];

  const RoutineSchedule.daily(
      {required int hourOfDay, required int minuteOfHour})
      : kind = 'daily',
        at = null,
        seconds = null,
        hour = hourOfDay,
        minute = minuteOfHour,
        weekdays = const [];

  const RoutineSchedule.weekly({
    required List<int> days,
    required int hourOfDay,
    required int minuteOfHour,
  })  : kind = 'weekly',
        at = null,
        seconds = null,
        hour = hourOfDay,
        minute = minuteOfHour,
        weekdays = days;

  factory RoutineSchedule.fromJson(Map<String, dynamic> json) {
    return RoutineSchedule(
      kind: json['kind'] as String? ?? 'other',
      at: _parseDate(json['at']),
      seconds: (json['seconds'] as num?)?.toInt(),
      hour: (json['hour'] as num?)?.toInt(),
      minute: (json['minute'] as num?)?.toInt(),
      weekdays: [
        if (json['weekdays'] is List)
          for (final d in json['weekdays'] as List)
            if (d is num) d.toInt(),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    switch (kind) {
      case 'once':
        return {'kind': kind, 'at': _iso(at ?? DateTime.now())};
      case 'interval':
        return {'kind': kind, 'seconds': seconds ?? 60};
      case 'daily':
        return {'kind': kind, 'hour': hour ?? 0, 'minute': minute ?? 0};
      case 'weekly':
        return {
          'kind': kind,
          'weekdays': weekdays,
          'hour': hour ?? 0,
          'minute': minute ?? 0,
        };
      default:
        return {'kind': kind};
    }
  }

  /// Texto curto para a lista.
  String describe() {
    switch (kind) {
      case 'once':
        return at == null ? 'Uma vez' : 'Uma vez em ${_fmtDateTime(at!)}';
      case 'interval':
        final s = seconds ?? 0;
        if (s % 3600 == 0 && s >= 3600) return 'A cada ${s ~/ 3600} h';
        if (s % 60 == 0 && s >= 60) return 'A cada ${s ~/ 60} min';
        return 'A cada $s s';
      case 'daily':
        return 'Todo dia às ${_fmtTime(hour, minute)}';
      case 'weekly':
        final names = weekdays.map(_weekdayName).join(', ');
        return '$names às ${_fmtTime(hour, minute)}';
      default:
        return 'Outro agendamento';
    }
  }
}

/// Condição de término: `never`, `afterCount` ou `onDate`.
class RoutineEndRepeat {
  final String kind;
  final int? count; // afterCount
  final DateTime? date; // onDate

  const RoutineEndRepeat({required this.kind, this.count, this.date});

  const RoutineEndRepeat.never()
      : kind = 'never',
        count = null,
        date = null;

  const RoutineEndRepeat.afterCount(int n)
      : kind = 'afterCount',
        count = n,
        date = null;

  const RoutineEndRepeat.onDate(DateTime d)
      : kind = 'onDate',
        count = null,
        date = d;

  factory RoutineEndRepeat.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RoutineEndRepeat.never();
    return RoutineEndRepeat(
      kind: json['kind'] as String? ?? 'never',
      count: (json['count'] as num?)?.toInt(),
      date: _parseDate(json['date']),
    );
  }

  Map<String, dynamic> toJson() {
    switch (kind) {
      case 'afterCount':
        return {'kind': kind, 'count': count ?? 1};
      case 'onDate':
        return {'kind': kind, 'date': _iso(date ?? DateTime.now())};
      default:
        return {'kind': 'never'};
    }
  }

  String describe() {
    switch (kind) {
      case 'afterCount':
        return 'Após ${count ?? 0} execuções';
      case 'onDate':
        return date == null ? 'Até uma data' : 'Até ${_fmtDate(date!)}';
      case 'never':
        return 'Nunca termina';
      default:
        return 'Outro término';
    }
  }
}

class Routine {
  final String id;
  final String name;
  final String workspaceId;

  /// Terminal alvo. Ausente = lembrete (notifica e não roda comando).
  final String? terminalId;
  final String prompt;
  final String? preRunScript;
  final bool skipIfBusy;
  final RoutineSchedule schedule;
  final RoutineEndRepeat endRepeat;
  final bool notifyOnFire;
  final bool isEnabled;

  /// Campos do host; ignorados em escritas.
  final int fireCount;
  final DateTime? lastFiredAt;
  final DateTime createdAt;

  const Routine({
    required this.id,
    required this.name,
    required this.workspaceId,
    this.terminalId,
    required this.prompt,
    this.preRunScript,
    this.skipIfBusy = false,
    required this.schedule,
    this.endRepeat = const RoutineEndRepeat.never(),
    this.notifyOnFire = true,
    this.isEnabled = true,
    this.fireCount = 0,
    this.lastFiredAt,
    required this.createdAt,
  });

  bool get isReminder => terminalId == null;

  factory Routine.fromJson(Map<String, dynamic> json) {
    return Routine(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      terminalId: json['terminalId'] as String?,
      prompt: json['prompt'] as String? ?? '',
      preRunScript: json['preRunScript'] as String?,
      skipIfBusy: json['skipIfBusy'] as bool? ?? false,
      schedule: RoutineSchedule.fromJson(
        (json['schedule'] as Map?)?.cast<String, dynamic>() ??
            const {'kind': 'other'},
      ),
      endRepeat: RoutineEndRepeat.fromJson(
        (json['endRepeat'] as Map?)?.cast<String, dynamic>(),
      ),
      notifyOnFire: json['notifyOnFire'] as bool? ?? false,
      isEnabled: json['isEnabled'] as bool? ?? false,
      fireCount: (json['fireCount'] as num?)?.toInt() ?? 0,
      lastFiredAt: _parseDate(json['lastFiredAt']),
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
    );
  }

  /// Corpo de POST/PUT. Campos opcionais ausentes são omitidos (nunca `null`).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'workspaceId': workspaceId,
      if (terminalId != null) 'terminalId': terminalId,
      'prompt': prompt,
      if (preRunScript != null && preRunScript!.isNotEmpty)
        'preRunScript': preRunScript,
      'skipIfBusy': skipIfBusy,
      'schedule': schedule.toJson(),
      'endRepeat': endRepeat.toJson(),
      'notifyOnFire': notifyOnFire,
      'isEnabled': isEnabled,
      'createdAt': _iso(createdAt),
    };
  }

  Routine copyWith({
    String? name,
    String? workspaceId,
    String? terminalId,
    bool clearTerminal = false,
    String? prompt,
    String? preRunScript,
    bool? skipIfBusy,
    RoutineSchedule? schedule,
    RoutineEndRepeat? endRepeat,
    bool? notifyOnFire,
    bool? isEnabled,
  }) {
    return Routine(
      id: id,
      name: name ?? this.name,
      workspaceId: workspaceId ?? this.workspaceId,
      terminalId: clearTerminal ? null : (terminalId ?? this.terminalId),
      prompt: prompt ?? this.prompt,
      preRunScript: preRunScript ?? this.preRunScript,
      skipIfBusy: skipIfBusy ?? this.skipIfBusy,
      schedule: schedule ?? this.schedule,
      endRepeat: endRepeat ?? this.endRepeat,
      notifyOnFire: notifyOnFire ?? this.notifyOnFire,
      isEnabled: isEnabled ?? this.isEnabled,
      fireCount: fireCount,
      lastFiredAt: lastFiredAt,
      createdAt: createdAt,
    );
  }
}

/// Alvo possível de uma rotina: um terminal, com workspace e andar.
class RoutineTarget {
  final String id;
  final String name;
  final String? icon;
  final String workspaceId;
  final String? floorId;
  final String? floorName;

  const RoutineTarget({
    required this.id,
    required this.name,
    this.icon,
    required this.workspaceId,
    this.floorId,
    this.floorName,
  });

  factory RoutineTarget.fromJson(Map<String, dynamic> json) {
    return RoutineTarget(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String?,
      workspaceId: json['workspaceId'] as String? ?? '',
      floorId: json['floorId'] as String?,
      floorName: json['floorName'] as String?,
    );
  }
}

/// Uma execução registrada no histórico.
/// `outcome`: sentToTerminal, terminalNotRunning, reminder, skippedByScript, skippedWhileBusy.
class RoutineFireRecord {
  final String id;
  final String routineId;
  final String routineName;
  final String prompt;
  final DateTime firedAt;
  final String outcome;
  final String? terminalName;

  const RoutineFireRecord({
    required this.id,
    required this.routineId,
    required this.routineName,
    required this.prompt,
    required this.firedAt,
    required this.outcome,
    this.terminalName,
  });

  factory RoutineFireRecord.fromJson(Map<String, dynamic> json) {
    return RoutineFireRecord(
      id: json['id'] as String? ?? '',
      routineId: json['routineId'] as String? ?? '',
      routineName: json['routineName'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      firedAt:
          _parseDate(json['firedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      outcome: json['outcome'] as String? ?? 'other',
      terminalName: json['terminalName'] as String?,
    );
  }

  String get outcomeLabel {
    switch (outcome) {
      case 'sentToTerminal':
        return 'Enviada ao terminal';
      case 'terminalNotRunning':
        return 'Terminal não está rodando';
      case 'reminder':
        return 'Lembrete';
      case 'skippedByScript':
        return 'Pulada pelo script';
      case 'skippedWhileBusy':
        return 'Pulada (terminal ocupado)';
      default:
        return outcome;
    }
  }
}

/// Resposta de `GET /api/routines`.
class RoutinesSnapshot {
  final List<Routine> routines;
  final List<RoutineFireRecord> history;
  final List<RoutineTarget> targets;

  const RoutinesSnapshot({
    required this.routines,
    required this.history,
    required this.targets,
  });

  factory RoutinesSnapshot.fromJson(Map<String, dynamic> json) {
    return RoutinesSnapshot(
      routines: [
        for (final r in (json['routines'] as List? ?? const []))
          Routine.fromJson((r as Map).cast<String, dynamic>()),
      ],
      history: [
        for (final h in (json['history'] as List? ?? const []))
          RoutineFireRecord.fromJson((h as Map).cast<String, dynamic>()),
      ],
      targets: [
        for (final t in (json['targets'] as List? ?? const []))
          RoutineTarget.fromJson((t as Map).cast<String, dynamic>()),
      ],
    );
  }
}

/// Ações de `POST /api/routines/{id}/action`.
enum RoutineAction {
  run('run'),
  enable('enable'),
  disable('disable');

  final String wire;
  const RoutineAction(this.wire);
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

String _iso(DateTime d) => d.toUtc().toIso8601String();

String _two(int n) => n.toString().padLeft(2, '0');

String _fmtTime(int? h, int? m) => '${_two(h ?? 0)}:${_two(m ?? 0)}';

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  return '${_two(l.day)}/${_two(l.month)}/${l.year}';
}

String _fmtDateTime(DateTime d) {
  final l = d.toLocal();
  return '${_fmtDate(l)} ${_two(l.hour)}:${_two(l.minute)}';
}

String _weekdayName(int d) {
  const names = ['', 'Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
  return d >= 1 && d <= 7 ? names[d] : '?';
}
