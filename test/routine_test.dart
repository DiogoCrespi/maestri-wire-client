import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/routine.dart';

void main() {
  const ws = '09A7826F-6C8C-42DE-9E07-A41996DF929F';

  test('lê GET /api/routines: rotinas, histórico e alvos', () {
    final snap = RoutinesSnapshot.fromJson({
      'routines': [
        {
          'id': 'AAAAAAAA-0000-4000-8000-000000000001',
          'name': 'Diária',
          'workspaceId': ws,
          'terminalId': 'BBBBBBBB-0000-4000-8000-000000000002',
          'prompt': 'rode os testes',
          'skipIfBusy': true,
          'schedule': {'kind': 'daily', 'hour': 9, 'minute': 5},
          'endRepeat': {'kind': 'afterCount', 'count': 3},
          'notifyOnFire': true,
          'isEnabled': true,
          'fireCount': 2,
          'lastFiredAt': '2026-10-10T12:00:00Z',
          'createdAt': '2026-10-01T10:00:00Z',
        },
        {
          'id': 'AAAAAAAA-0000-4000-8000-000000000003',
          'name': 'Lembrete',
          'workspaceId': ws,
          'prompt': 'pagar fatura',
          'schedule': {
            'kind': 'weekly',
            'weekdays': [2, 4],
            'hour': 18,
            'minute': 0
          },
          'endRepeat': {'kind': 'never'},
          'isEnabled': false,
          'createdAt': '2026-10-01T10:00:00Z',
        },
      ],
      'history': [
        {
          'id': 'H1',
          'routineId': 'AAAAAAAA-0000-4000-8000-000000000001',
          'routineName': 'Diária',
          'prompt': 'rode os testes',
          'firedAt': '2026-10-10T12:00:00Z',
          'outcome': 'sentToTerminal',
          'terminalName': 'Claude',
        },
      ],
      'targets': [
        {
          'id': 'BBBBBBBB-0000-4000-8000-000000000002',
          'name': 'Claude',
          'icon': 'sparkles',
          'workspaceId': ws,
          'floorId': 'CCCCCCCC-0000-4000-8000-000000000004',
          'floorName': 'Principal',
        },
      ],
    });

    expect(snap.routines.length, 2);
    final daily = snap.routines[0];
    expect(daily.isReminder, isFalse);
    expect(daily.schedule.kind, 'daily');
    expect(daily.schedule.describe(), 'Todo dia às 09:05');
    expect(daily.endRepeat.describe(), 'Após 3 execuções');
    expect(daily.fireCount, 2);

    final reminder = snap.routines[1];
    expect(reminder.isReminder, isTrue);
    expect(reminder.schedule.weekdays, [2, 4]);
    expect(reminder.schedule.describe(), 'Seg, Qua às 18:00');

    expect(snap.history.single.outcomeLabel, 'Enviada ao terminal');
    expect(snap.targets.single.floorName, 'Principal');
  });

  test('toJson omite campos opcionais ausentes e não envia campos do host', () {
    final routine = Routine(
      id: 'AAAAAAAA-0000-4000-8000-000000000003',
      name: 'Lembrete',
      workspaceId: ws,
      prompt: 'pagar fatura',
      schedule: RoutineSchedule.daily(hourOfDay: 8, minuteOfHour: 30),
      isEnabled: false,
      fireCount: 7,
      lastFiredAt: DateTime.utc(2026, 10, 10),
      createdAt: DateTime.utc(2026, 10, 1, 10),
    );

    final json = routine.toJson();
    expect(json.containsKey('terminalId'), isFalse);
    expect(json.containsKey('preRunScript'), isFalse);
    expect(json.containsValue(null), isFalse);
    expect(json.containsKey('fireCount'), isFalse);
    expect(json.containsKey('lastFiredAt'), isFalse);
    expect(json['schedule'], {'kind': 'daily', 'hour': 8, 'minute': 30});
    expect(json['endRepeat'], {'kind': 'never'});
    expect(json['isEnabled'], isFalse);
    expect(json['createdAt'], '2026-10-01T10:00:00.000Z');
  });

  test('copyWith troca o terminal para lembrete com clearTerminal', () {
    final base = Routine(
      id: 'X',
      name: 'n',
      workspaceId: ws,
      terminalId: 'T',
      prompt: 'p',
      schedule: RoutineSchedule.interval(3600),
      createdAt: DateTime.utc(2026),
    );
    expect(base.copyWith(name: 'novo').terminalId, 'T');
    expect(base.copyWith(clearTerminal: true).isReminder, isTrue);
    expect(
        base.copyWith(clearTerminal: true).toJson().containsKey('terminalId'),
        isFalse);
  });

  test('agendamentos: serialização e descrição', () {
    expect(RoutineSchedule.interval(3600).toJson(),
        {'kind': 'interval', 'seconds': 3600});
    expect(RoutineSchedule.interval(3600).describe(), 'A cada 1 h');
    expect(RoutineSchedule.interval(90).describe(), 'A cada 90 s');
    expect(
      RoutineSchedule.weekly(days: [1, 7], hourOfDay: 7, minuteOfHour: 0)
          .toJson(),
      {
        'kind': 'weekly',
        'weekdays': [1, 7],
        'hour': 7,
        'minute': 0
      },
    );
    final once = RoutineSchedule.once(DateTime.utc(2030, 1, 2, 3, 4, 5));
    expect(once.toJson(), {'kind': 'once', 'at': '2030-01-02T03:04:05.000Z'});
  });

  test('tipos desconhecidos viram "outro" sem falhar', () {
    final s = RoutineSchedule.fromJson({'kind': 'lunar'});
    expect(s.kind, 'lunar');
    expect(s.describe(), 'Outro agendamento');
    final rec = RoutineFireRecord.fromJson({
      'id': 'H',
      'routineId': 'R',
      'routineName': 'n',
      'prompt': 'p',
      'firedAt': '2026-10-10T12:00:00Z',
      'outcome': 'novoDesfecho',
    });
    expect(rec.outcomeLabel, 'novoDesfecho');
  });

  test('ações do endpoint /action', () {
    expect(RoutineAction.run.wire, 'run');
    expect(RoutineAction.enable.wire, 'enable');
    expect(RoutineAction.disable.wire, 'disable');
  });
}
