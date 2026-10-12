import '../../models/floor.dart';
import '../../models/floor_hooks.dart';
import 'api_floors.dart';
import 'wire_client.dart';

/// Hooks de andar (capability floorHooks, owner). Só o host executa os comandos.
/// Contrato: notes/maestri-wire.md, "Hooks de andar".
extension HooksApi on WireClient {
  String _hooksPath(String workspaceId) =>
      '/api/workspaces/${Uri.encodeComponent(workspaceId)}/hooks';

  /// GET /api/workspaces/{ws}/hooks — hooks do workspace e as execuções lembradas.
  Future<FloorHooksSnapshot> getFloorHooks(String workspaceId) async {
    final json = await hostGetJson(this, _hooksPath(workspaceId));
    return FloorHooksSnapshot.fromJson(json);
  }

  /// PUT /api/workspaces/{ws}/hooks — substitui os hooks inteiros.
  Future<void> putFloorHooks(String workspaceId, FloorHooks hooks) async {
    // O corpo é o próprio formato `hooks` (sem envelope).
    await hostRequestJson(this, 'PUT', _hooksPath(workspaceId), hooks.toJson());
  }

  /// POST …/floors/{id}/hooks. `action` é `run`, `stop` ou `runSection`:
  /// `commandId` para run/stop, `section` (setup, run, teardown) para runSection.
  Future<void> floorHookAction(
    String workspaceId,
    FloorMeta floor, {
    required String action,
    String? commandId,
    String? section,
  }) async {
    await hostRequestJson(
      this,
      'POST',
      floorPath(workspaceId, floor.queryValue, 'hooks'),
      {
        'action': action,
        if (commandId != null) 'commandId': commandId,
        if (section != null) 'section': section,
      },
    );
  }
}
