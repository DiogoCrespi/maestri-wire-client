import 'dart:convert';

/// Camada pura dos eventos do socket do feed (`/api/feed/stream`).
///
/// Sem Flutter e sem rede: parse das mensagens do servidor, controle de
/// sequência das mutações e builders das mensagens do cliente.
/// Contrato: notes/maestri-wire.md, seções "Socket do feed".

// ---------------------------------------------------------------------------
// Limites do cliente para a câmera (contrato: pan até 4000 pontos, zoom 0.25..4)
// ---------------------------------------------------------------------------

const double kFeedMaxPanPoints = 4000;
const double kFeedMinZoomFactor = 0.25;
const double kFeedMaxZoomFactor = 4;

// ---------------------------------------------------------------------------
// Mensagens servidor -> cliente
// ---------------------------------------------------------------------------

sealed class FeedMessage {
  const FeedMessage();
}

/// `{"type":"feed","snapshot":...}`. O snapshot fica cru: quem o modela é o
/// dono do FeedSnapshot.
final class FeedSnapshotMessage extends FeedMessage {
  final Map<String, dynamic> snapshot;
  const FeedSnapshotMessage(this.snapshot);
}

/// `{"type":"mutation","mutation":...}`.
final class FeedMutationMessage extends FeedMessage {
  final MutationEvent mutation;
  const FeedMutationMessage(this.mutation);
}

/// `{"type":"pong"}`.
final class FeedPongMessage extends FeedMessage {
  const FeedPongMessage();
}

/// Qualquer `type` desconhecido. O contrato manda ignorá-lo; o payload fica
/// disponível em [raw] caso o chamador queira.
final class FeedUnknownMessage extends FeedMessage {
  final String type;
  final Map<String, dynamic> raw;
  const FeedUnknownMessage(this.type, this.raw);
}

/// Faz o parse de uma mensagem crua do socket. Retorna `null` para JSON
/// inválido, objeto sem `type` ou mutação sem `sequence`/`epoch` válidos.
FeedMessage? parseFeedMessage(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  return parseFeedMessageMap(Map<String, dynamic>.from(decoded));
}

/// Igual a [parseFeedMessage], mas para um objeto já decodificado (o que
/// `FeedSocket.updates` já entrega).
FeedMessage? parseFeedMessageMap(Map<String, dynamic> json) {
  final type = _str(json, 'type');
  if (type == null) return null;
  switch (type) {
    case 'feed':
      final snapshot = json['snapshot'];
      if (snapshot is! Map) return null;
      return FeedSnapshotMessage(Map<String, dynamic>.from(snapshot));
    case 'mutation':
      final mutation = json['mutation'];
      if (mutation is! Map) return null;
      final event = MutationEvent.tryFromJson(Map<String, dynamic>.from(mutation));
      if (event == null) return null;
      return FeedMutationMessage(event);
    case 'pong':
      return const FeedPongMessage();
    default:
      return FeedUnknownMessage(type, json);
  }
}

// ---------------------------------------------------------------------------
// MutationEvent
// ---------------------------------------------------------------------------

class FeedFrame {
  final double x;
  final double y;
  final double width;
  final double height;

  const FeedFrame({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  static FeedFrame? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final x = _dbl(json, 'x');
    final y = _dbl(json, 'y');
    final width = _dbl(json, 'width');
    final height = _dbl(json, 'height');
    if (x == null || y == null || width == null || height == null) return null;
    return FeedFrame(x: x, y: y, width: width, height: height);
  }
}

class FeedPoint {
  final double x;
  final double y;

  const FeedPoint({required this.x, required this.y});

  /// Aceita `{x, y}` ou `[x, y]` (o Drawing do host usa a forma de lista).
  static FeedPoint? tryFromJson(Object? json) {
    if (json is Map) {
      final x = _dbl(json, 'x');
      final y = _dbl(json, 'y');
      if (x == null || y == null) return null;
      return FeedPoint(x: x, y: y);
    }
    if (json is List && json.length >= 2) {
      final x = json[0];
      final y = json[1];
      if (x is num && y is num) {
        return FeedPoint(x: x.toDouble(), y: y.toDouble());
      }
    }
    return null;
  }
}

class MutationActor {
  final String deviceId;
  final String deviceName;
  final String? role;

  const MutationActor({
    required this.deviceId,
    required this.deviceName,
    this.role,
  });

  static MutationActor? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final deviceId = _str(json, 'deviceId');
    final deviceName = _str(json, 'deviceName');
    if (deviceId == null || deviceName == null) return null;
    return MutationActor(
      deviceId: deviceId,
      deviceName: deviceName,
      role: _str(json, 'role'),
    );
  }
}

class MutationEvent {
  /// Repetido literalmente da requisição de origem. Não usar para dedupe.
  final String? mutationId;

  /// Denso e monotônico dentro de um [epoch].
  final int sequence;

  /// Identidade desta execução do servidor.
  final String epoch;

  /// Por onde a requisição passou. Nunca filtrar por ele.
  final String? floorId;
  final MutationActor? actor;
  final MutationKind kind;

  const MutationEvent({
    this.mutationId,
    required this.sequence,
    required this.epoch,
    this.floorId,
    this.actor,
    required this.kind,
  });

  static MutationEvent? tryFromJson(Map<String, dynamic> json) {
    final sequence = _int(json, 'sequence');
    final epoch = _str(json, 'epoch');
    if (sequence == null || epoch == null) return null;
    final kindJson = json['kind'];
    final kind = kindJson is Map
        ? MutationKind.fromJson(Map<String, dynamic>.from(kindJson))
        : const UnknownMutationKind('', {});
    return MutationEvent(
      mutationId: _str(json, 'mutationId'),
      sequence: sequence,
      epoch: epoch,
      floorId: _str(json, 'floorId'),
      actor: MutationActor.tryFromJson(json['actor']),
      kind: kind,
    );
  }
}

// ---------------------------------------------------------------------------
// MutationKind
// ---------------------------------------------------------------------------

sealed class MutationKind {
  const MutationKind();

  /// Nome do tipo como veio do servidor (`nodeMoved`, ...).
  String get kind;

  /// Um `kind` cujo tipo ou campos obrigatórios não foram reconhecidos vira
  /// [UnknownMutationKind], com o JSON original preservado.
  static MutationKind fromJson(Map<String, dynamic> json) {
    final kind = _str(json, 'kind') ?? '';
    final parsed = _parseKnownKind(kind, json);
    return parsed ?? UnknownMutationKind(kind, json);
  }
}

MutationKind? _parseKnownKind(String kind, Map<String, dynamic> json) {
  switch (kind) {
    case 'nodeMoved':
      final nodeId = _str(json, 'nodeId');
      final frame = FeedFrame.tryFromJson(json['frame']);
      if (nodeId == null || frame == null) return null;
      return NodeMovedKind(nodeId: nodeId, frame: frame);
    case 'nodeRenamed':
      final nodeIds = _strList(json['nodeIds']);
      final name = _str(json, 'name');
      if (nodeIds == null || name == null) return null;
      return NodeRenamedKind(nodeIds: nodeIds, name: name);
    case 'nodeCreated':
      final nodeId = _str(json, 'nodeId');
      final nodeKind = _str(json, 'nodeKind');
      if (nodeId == null || nodeKind == null) return null;
      return NodeCreatedKind(nodeId: nodeId, nodeKind: nodeKind);
    case 'nodeRemoved':
      final nodeId = _str(json, 'nodeId');
      if (nodeId == null) return null;
      return NodeRemovedKind(nodeId: nodeId);
    case 'nodeLockChanged':
      final nodeId = _str(json, 'nodeId');
      final isLocked = json['isLocked'];
      if (nodeId == null || isLocked is! bool) return null;
      return NodeLockChangedKind(nodeId: nodeId, isLocked: isLocked);
    case 'noteColorChanged':
      final nodeId = _str(json, 'nodeId');
      final color = _str(json, 'color');
      if (nodeId == null || color == null) return null;
      return NoteColorChangedKind(
        nodeId: nodeId,
        color: color,
        customColor: _str(json, 'customColor'),
      );
    case 'connectionAdded':
      final from = _str(json, 'fromNodeId');
      final to = _str(json, 'toNodeId');
      if (from == null || to == null) return null;
      return ConnectionAddedKind(fromNodeId: from, toNodeId: to);
    case 'connectionRemoved':
      final from = _str(json, 'fromNodeId');
      final to = _str(json, 'toNodeId');
      if (from == null || to == null) return null;
      return ConnectionRemovedKind(fromNodeId: from, toNodeId: to);
    case 'noteStackRailChanged':
      final stackNodeId = _str(json, 'stackNodeId');
      final members = _strList(json['memberNodeIds']);
      if (stackNodeId == null || members == null) return null;
      return NoteStackRailChangedKind(
        stackNodeId: stackNodeId,
        memberNodeIds: members,
        frontNoteId: _str(json, 'frontNoteId'),
      );
    case 'drawingAdded':
      final drawingId = _str(json, 'drawingId');
      if (drawingId == null) return null;
      return DrawingAddedKind(drawingId: drawingId);
    case 'drawingRemoved':
      final drawingId = _str(json, 'drawingId');
      if (drawingId == null) return null;
      return DrawingRemovedKind(drawingId: drawingId);
    case 'drawingMoved':
      final drawingId = _str(json, 'drawingId');
      final origin = FeedPoint.tryFromJson(json['origin']);
      if (drawingId == null || origin == null) return null;
      return DrawingMovedKind(drawingId: drawingId, origin: origin);
  }
  return null;
}

final class NodeMovedKind extends MutationKind {
  final String nodeId;
  final FeedFrame frame;
  const NodeMovedKind({required this.nodeId, required this.frame});
  @override
  String get kind => 'nodeMoved';
}

final class NodeRenamedKind extends MutationKind {
  final List<String> nodeIds;
  final String name;
  const NodeRenamedKind({required this.nodeIds, required this.name});
  @override
  String get kind => 'nodeRenamed';
}

final class NodeCreatedKind extends MutationKind {
  final String nodeId;
  final String nodeKind;
  const NodeCreatedKind({required this.nodeId, required this.nodeKind});
  @override
  String get kind => 'nodeCreated';
}

final class NodeRemovedKind extends MutationKind {
  final String nodeId;
  const NodeRemovedKind({required this.nodeId});
  @override
  String get kind => 'nodeRemoved';
}

final class NodeLockChangedKind extends MutationKind {
  final String nodeId;
  final bool isLocked;
  const NodeLockChangedKind({required this.nodeId, required this.isLocked});
  @override
  String get kind => 'nodeLockChanged';
}

final class NoteColorChangedKind extends MutationKind {
  final String nodeId;
  final String color;
  final String? customColor;
  const NoteColorChangedKind({
    required this.nodeId,
    required this.color,
    this.customColor,
  });
  @override
  String get kind => 'noteColorChanged';
}

final class ConnectionAddedKind extends MutationKind {
  final String fromNodeId;
  final String toNodeId;
  const ConnectionAddedKind({required this.fromNodeId, required this.toNodeId});
  @override
  String get kind => 'connectionAdded';
}

final class ConnectionRemovedKind extends MutationKind {
  final String fromNodeId;
  final String toNodeId;
  const ConnectionRemovedKind({
    required this.fromNodeId,
    required this.toNodeId,
  });
  @override
  String get kind => 'connectionRemoved';
}

final class NoteStackRailChangedKind extends MutationKind {
  final String stackNodeId;
  final List<String> memberNodeIds;
  final String? frontNoteId;
  const NoteStackRailChangedKind({
    required this.stackNodeId,
    required this.memberNodeIds,
    this.frontNoteId,
  });
  @override
  String get kind => 'noteStackRailChanged';
}

final class DrawingAddedKind extends MutationKind {
  final String drawingId;
  const DrawingAddedKind({required this.drawingId});
  @override
  String get kind => 'drawingAdded';
}

final class DrawingRemovedKind extends MutationKind {
  final String drawingId;
  const DrawingRemovedKind({required this.drawingId});
  @override
  String get kind => 'drawingRemoved';
}

final class DrawingMovedKind extends MutationKind {
  final String drawingId;
  final FeedPoint origin;
  const DrawingMovedKind({required this.drawingId, required this.origin});
  @override
  String get kind => 'drawingMoved';
}

/// Tipo novo do servidor (ou campos faltando). O [raw] guarda o JSON inteiro
/// do `kind` para quem quiser inspecionar.
final class UnknownMutationKind extends MutationKind {
  @override
  final String kind;
  final Map<String, dynamic> raw;
  const UnknownMutationKind(this.kind, this.raw);
}

// ---------------------------------------------------------------------------
// MutationTracker
// ---------------------------------------------------------------------------

enum MutationDecision {
  /// Próxima da sequência: aplicar.
  apply,

  /// Já visto (mesmo epoch, sequence <= última): ignorar.
  duplicate,

  /// Epoch novo ou lacuna de sequence: ressincronizar pelo snapshot.
  resync,
}

/// Decide, para cada evento recebido, se aplica, ignora ou ressincroniza.
///
/// Dedupe é por (epoch, sequence), nunca por mutationId. A baseline começa
/// vazia: o primeiro evento a estabelece. Chame [reset] ao reconectar.
class MutationTracker {
  String? _epoch;
  int? _lastSequence;

  String? get epoch => _epoch;
  int? get lastSequence => _lastSequence;

  MutationDecision accept(MutationEvent event) {
    final currentEpoch = _epoch;
    final last = _lastSequence;

    if (currentEpoch == null || last == null) {
      _epoch = event.epoch;
      _lastSequence = event.sequence;
      return MutationDecision.apply;
    }

    if (event.epoch != currentEpoch) {
      // Servidor reiniciou: a sequência antiga não vale mais.
      _epoch = event.epoch;
      _lastSequence = event.sequence;
      return MutationDecision.resync;
    }

    if (event.sequence <= last) {
      return MutationDecision.duplicate;
    }

    _lastSequence = event.sequence;
    if (event.sequence == last + 1) {
      return MutationDecision.apply;
    }

    // Lacuna: eventos perdidos. O snapshot cobre o que faltou.
    return MutationDecision.resync;
  }

  /// Esquece a baseline (ex.: após reconectar, antes do snapshot).
  void reset() {
    _epoch = null;
    _lastSequence = null;
  }
}

// ---------------------------------------------------------------------------
// Builders cliente -> servidor
// ---------------------------------------------------------------------------

/// `presence` com o id de **nó** (não de terminal) que a pessoa tem aberto.
String presenceNodeMessage(String nodeId) =>
    jsonEncode({'type': 'presence', 'nodeId': nodeId});

/// `presence` com um ponto em coordenadas do canvas.
String presencePointMessage(double x, double y) {
  if (!x.isFinite || !y.isFinite) {
    throw ArgumentError('presencePointMessage: coordenadas não finitas');
  }
  return jsonEncode({
    'type': 'presence',
    'point': {'x': x, 'y': y},
  });
}

/// `presence` sem nada: lugar nenhum. Enviar ao sair de um nó.
String presenceClearMessage() => jsonEncode({'type': 'presence'});

String pingMessage() => jsonEncode({'type': 'ping'});

/// `camera` (capability `cameraControl`). Um frame pequeno de joystick/roda.
///
/// - `dx`/`dy` em pontos de tela, limitados a ±[kFeedMaxPanPoints]. Sem pan
///   (0,0) o campo `pan` é omitido.
/// - `zoom` é um fator multiplicativo, limitado a
///   [kFeedMinZoomFactor]..[kFeedMaxZoomFactor]. Omitido se `null`.
/// Não-finitos viram 0 (pan) ou são omitidos (zoom).
String cameraMessage({double dx = 0, double dy = 0, double? zoom}) {
  final body = <String, Object>{'type': 'camera'};
  final px = _clampPan(dx);
  final py = _clampPan(dy);
  if (px != 0 || py != 0) {
    body['pan'] = {'dx': px, 'dy': py};
  }
  if (zoom != null && zoom.isFinite) {
    body['zoom'] = zoom.clamp(kFeedMinZoomFactor, kFeedMaxZoomFactor).toDouble();
  }
  return jsonEncode(body);
}

double _clampPan(double v) {
  if (!v.isFinite) return 0;
  return v.clamp(-kFeedMaxPanPoints, kFeedMaxPanPoints).toDouble();
}

// ---------------------------------------------------------------------------
// Helpers de leitura tolerante
// ---------------------------------------------------------------------------

String? _str(Map<dynamic, dynamic> json, String key) {
  final v = json[key];
  return v is String ? v : null;
}

int? _int(Map<dynamic, dynamic> json, String key) {
  final v = json[key];
  if (v is! num) return null;
  if (v != v.roundToDouble()) return null;
  return v.toInt();
}

double? _dbl(Map<dynamic, dynamic> json, String key) {
  final v = json[key];
  return v is num ? v.toDouble() : null;
}

List<String>? _strList(Object? v) {
  if (v is! List) return null;
  final out = <String>[];
  for (final item in v) {
    if (item is! String) return null;
    out.add(item);
  }
  return out;
}
