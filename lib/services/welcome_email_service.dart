import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum WelcomeEmailStatus {
  sent,
  notConfigured,
  invalidConfiguration,
  serverUnavailable,
  serverRejected,
  failed,
  verified,
  invalidCode,
}

class WelcomeEmailService {
  const WelcomeEmailService();

  static const _baseEndpoint = String.fromEnvironment(
    'ACCOUNT_API_URL',
    defaultValue: 'http://10.0.2.2:6500',
  );
  static const _allowEmulatorHttp = bool.fromEnvironment(
    'ALLOW_INSECURE_MAIL_API',
    defaultValue: true,
  );

  Future<WelcomeEmailStatus> sendWelcome({
    required String email,
    required String firstName,
  }) async {
    return _post('/verification-email', {
      'email': email.trim(),
      'firstName': firstName.trim(),
    }, success: WelcomeEmailStatus.sent);
  }

  Future<WelcomeEmailStatus> verifyCode({required String email, required String code}) async =>
      (await verifyCodeForToken(email: email, code: code)).status;

  /// Vérifie le code et retourne aussi le jeton serveur prouvant la possession de l'adresse.
  Future<({WelcomeEmailStatus status, String? token})> verifyCodeForToken({
    required String email,
    required String code,
  }) async {
    String? token;
    final status = await _post(
      '/verify-email',
      {'email': email.trim(), 'code': code.trim()},
      success: WelcomeEmailStatus.verified,
      onBody: (body) {
        final decoded = jsonDecode(body);
        if (decoded is Map) token = decoded['verificationToken'] as String?;
      },
    );
    return (status: status, token: token);
  }

  Future<WelcomeEmailStatus> _post(
    String path,
    Map<String, String> payload, {
    required WelcomeEmailStatus success,
    void Function(String body)? onBody,
  }) async {
    if (_baseEndpoint.trim().isEmpty) return WelcomeEmailStatus.notConfigured;

    final base = Uri.tryParse(_baseEndpoint);
    final uri = base?.replace(path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path');
    final isSecure = uri?.scheme == 'https';
    final isLocalEmulatorDebug = kDebugMode &&
        _allowEmulatorHttp &&
        uri?.scheme == 'http' &&
        uri?.host == '10.0.2.2';
    if (uri == null || (!isSecure && !isLocalEmulatorDebug) || uri.host.isEmpty) {
      return WelcomeEmailStatus.invalidConfiguration;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri).timeout(
        const Duration(seconds: 12),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(
        jsonEncode(payload),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        onBody?.call(body);
        return success;
      }
      if (response.statusCode == 400 && path == '/verify-email') return WelcomeEmailStatus.invalidCode;
      return WelcomeEmailStatus.serverRejected;
    } on Object {
      return WelcomeEmailStatus.serverUnavailable;
    } finally {
      client.close(force: true);
    }
  }
}
