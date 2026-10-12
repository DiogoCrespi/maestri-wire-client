import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maestri_wire_client/core/network/tls_pinning.dart';

void main() {
  // test/fixtures/test_cert.der é um certificado autoassinado de teste.
  // Os valores de referência foram calculados com o openssl:
  //   openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
  //   openssl dgst -sha256 -binary cert.der | base64
  const expectedSpki = 'zL3EC9Do68aH664+zUKxklDDyeSvOaJhboK/9eiuXrs=';

  late Uint8List certDer;

  setUpAll(() {
    certDer = Uint8List.fromList(File('test/fixtures/test_cert.der').readAsBytesSync());
  });

  test('extrai a SPKI e calcula o mesmo SHA-256 que o openssl', () {
    expect(spkiSha256Base64(certDer), expectedSpki);
  });

  test('a SPKI é um SEQUENCE DER válido que ocupa parte do certificado', () {
    final spki = spkiDer(certDer);
    expect(spki.first, 0x30);
    expect(spki.length, lessThan(certDer.length));
    // a SPKI aparece inteira dentro do certificado
    expect(_indexOf(certDer, spki), greaterThan(0));
  });

  test('entrada truncada lança FormatException em vez de ler fora do buffer', () {
    final truncated = Uint8List.sublistView(certDer, 0, 40);
    expect(() => spkiDer(truncated), throwsFormatException);
  });
}

int _indexOf(Uint8List haystack, Uint8List needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
