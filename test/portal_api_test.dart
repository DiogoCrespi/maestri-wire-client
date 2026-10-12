import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/network/api_devices.dart';
import 'package:maestri_wire_client/core/network/api_portals.dart';

void main() {
  group('caminhos de portal', () {
    test('ações montam /api/portals/{id}/{action}', () {
      expect(portalPath('9694d25f', 'reload'), '/api/portals/9694d25f/reload');
      expect(
          portalPath('9694d25f', 'navigate'), '/api/portals/9694d25f/navigate');
      expect(portalPath('9694d25f'), '/api/portals/9694d25f');
    });
  });

  group('validatePortalUrl', () {
    test('aceita http e https e apara espaços', () {
      expect(validatePortalUrl('  https://exemplo.com/a?b=1 '),
          'https://exemplo.com/a?b=1');
      expect(validatePortalUrl('http://192.168.1.10:8080'),
          'http://192.168.1.10:8080');
    });

    test('recusa outros esquemas, sem host e texto livre', () {
      expect(
          () => validatePortalUrl('javascript:alert(1)'), throwsArgumentError);
      expect(
          () => validatePortalUrl('file:///etc/passwd'), throwsArgumentError);
      expect(() => validatePortalUrl('https://'), throwsArgumentError);
      expect(() => validatePortalUrl('exemplo.com'), throwsArgumentError);
      expect(() => validatePortalUrl(''), throwsArgumentError);
    });
  });

  group('caminhos de dispositivo', () {
    test('devicePath monta rotas de dispositivo', () {
      expect(devicePath('6516AF12'), '/api/devices/6516AF12');
      expect(devicePath('6516AF12', 'role'), '/api/devices/6516AF12/role');
      expect(devicePath('6516AF12', 'name'), '/api/devices/6516AF12/name');
    });
  });
}
