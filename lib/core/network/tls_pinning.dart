import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// TLS Pinning do host Maestri Wire.
///
/// O host usa certificado autoassinado. Um certificado só é aceito se o SHA-256
/// da sua SubjectPublicKeyInfo (SPKI) — ou do DER completo, formato usado em
/// versões anteriores — bater com o `serverKeyHash` salvo no pareamento.
///
/// Sem hash salvo (pareamento manual), o primeiro certificado visto é aceito e
/// devolvido em [onObserved] para ser fixado (trust on first use).
HttpClient createPinnedHttpClient({
  String? expectedPin,
  void Function(String pin)? onObserved,
}) {
  final client = HttpClient();

  // O callback só é chamado para certificados que falham na validação padrão,
  // ou seja, os autoassinados do host. Um certificado público válido passa direto.
  client.badCertificateCallback = (X509Certificate cert, String host, int port) {
    final der = cert.der;
    final spkiPin = spkiSha256Base64(der);

    if (expectedPin == null || expectedPin.isEmpty) {
      onObserved?.call(spkiPin);
      return true;
    }

    final fullPin = base64Encode(sha256.convert(der).bytes);
    return expectedPin == spkiPin || expectedPin == fullPin;
  };

  return client;
}

/// SHA-256 da SPKI de um certificado X.509 em DER, em base64.
String spkiSha256Base64(Uint8List certDer) {
  return base64Encode(sha256.convert(spkiDer(certDer)).bytes);
}

/// Extrai a SubjectPublicKeyInfo (campo `subjectPublicKeyInfo` do TBSCertificate)
/// de um certificado X.509 em DER.
///
/// Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
/// TBSCertificate ::= SEQUENCE { [0] version?, serialNumber, signature, issuer,
///                               validity, subject, subjectPublicKeyInfo, ... }
Uint8List spkiDer(Uint8List certDer) {
  final (certStart, _) = _contentOf(certDer, 0);
  final (tbsStart, _) = _contentOf(certDer, certStart);

  var pos = tbsStart;
  // version é opcional e marcado com [0] EXPLICIT (0xA0)
  if (certDer[pos] == 0xA0) {
    pos = _endOf(certDer, pos);
  }
  // serialNumber, signature, issuer, validity, subject
  for (var i = 0; i < 5; i++) {
    pos = _endOf(certDer, pos);
  }

  final end = _endOf(certDer, pos);
  return Uint8List.sublistView(certDer, pos, end);
}

/// Retorna (início, fim) do conteúdo do TLV que começa em [offset].
(int, int) _contentOf(Uint8List der, int offset) {
  if (offset + 2 > der.length) {
    throw const FormatException('Certificado DER truncado');
  }
  var pos = offset + 1; // tags usadas na estrutura do certificado têm 1 byte
  var length = der[pos++];
  if (length & 0x80 != 0) {
    final bytes = length & 0x7f;
    if (bytes == 0 || bytes > 4 || pos + bytes > der.length) {
      throw const FormatException('Comprimento DER inválido');
    }
    length = 0;
    for (var i = 0; i < bytes; i++) {
      length = (length << 8) | der[pos++];
    }
  }
  final end = pos + length;
  if (end > der.length) {
    throw const FormatException('Certificado DER truncado');
  }
  return (pos, end);
}

/// Posição logo após o TLV que começa em [offset].
int _endOf(Uint8List der, int offset) => _contentOf(der, offset).$2;
