import 'dart:convert';

import 'package:crypto/crypto.dart';

class AwsSigV4 {
  AwsSigV4({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.service,
    this.sessionToken,
  });

  final String accessKey;
  final String secretKey;
  final String region;
  final String service;
  final String? sessionToken;

  Map<String, String> headers({
    required String method,
    required Uri uri,
    required String body,
    required DateTime now,
    String contentType = 'application/x-www-form-urlencoded',
  }) {
    final amzDate = _amzDate(now.toUtc());
    final dateStamp = amzDate.substring(0, 8);
    final host = uri.host;
    final payloadHash = sha256.convert(utf8.encode(body)).toString();

    final headerMap = <String, String>{
      'content-type': contentType,
      'host': host,
      'x-amz-date': amzDate,
    };
    final token = sessionToken?.trim();
    if (token != null && token.isNotEmpty) {
      headerMap['x-amz-security-token'] = token;
    }

    final signedNames = headerMap.keys.toList()..sort();
    final canonicalHeaders = signedNames.map((name) => '$name:${headerMap[name]}\n').join();
    final signedHeaderStr = signedNames.join(';');
    final canonicalQuery = uri.hasQuery ? uri.query : '';
    final canonicalRequest = [
      method.toUpperCase(),
      uri.path.isEmpty ? '/' : uri.path,
      canonicalQuery,
      canonicalHeaders,
      signedHeaderStr,
      payloadHash,
    ].join('\n');

    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _signingKey(dateStamp);
    final signature = _hmac(signingKey, utf8.encode(stringToSign)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return {
      'Content-Type': contentType,
      'X-Amz-Date': amzDate,
      if (token != null && token.isNotEmpty) 'X-Amz-Security-Token': token,
      'Authorization':
          'AWS4-HMAC-SHA256 Credential=$accessKey/$credentialScope, SignedHeaders=$signedHeaderStr, Signature=$signature',
    };
  }

  List<int> _signingKey(String dateStamp) {
    final kDate = _hmac(utf8.encode('AWS4$secretKey'), utf8.encode(dateStamp));
    final kRegion = _hmac(kDate, utf8.encode(region));
    final kService = _hmac(kRegion, utf8.encode(service));
    return _hmac(kService, utf8.encode('aws4_request'));
  }

  List<int> _hmac(List<int> key, List<int> data) => Hmac(sha256, key).convert(data).bytes;

  String _amzDate(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }
}
