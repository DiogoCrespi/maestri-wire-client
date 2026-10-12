import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/models/cable_tie.dart';

void main() {
  test('lê os pontos roteados e o estado ativo enviados pelo host', () {
    final cable = CableTie.fromJson({
      'id': 'c1',
      'fromNodeId': 'a',
      'toNodeId': 'b',
      'kind': 'terminal',
      'isActive': true,
      'points': [
        {'x': 9740, 'y': 9110},
        {'x': 9480.5, 'y': 9150},
        {'bad': true},
      ],
    });

    expect(cable.fromNodeId, 'a');
    expect(cable.toNodeId, 'b');
    expect(cable.isFlowing, isTrue);
    expect(cable.points, [const Offset(9740, 9110), const Offset(9480.5, 9150)]);
  });

  test('sem pontos o cabo fica vazio e usa o desenho entre os nós', () {
    final cable = CableTie.fromJson({'id': 'c2', 'from': 'a', 'to': 'b'});
    expect(cable.points, isEmpty);
    expect(cable.isFlowing, isFalse);
  });
}
