import 'dart:convert';
import 'dart:io';

enum WelcomeEmailStatus { sent, notConfigured, failed, verified, invalidCode }

class WelcomeEmailService {
  const WelcomeEmailService();

  static const _baseEndpoint = String.fromEnvironment(
    'ACCOUNT_API_URL',
    defaultValue: '',
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

  Future<WelcomeEmailStatus> verifyCode({required String email, required String code}) =>
      _post('/verify-email', {'email': email.trim(), 'code': code.trim()}, success: WelcomeEmailStatus.verified);

  Future<WelcomeEmailStatus> _post(String path, Map<String, String> payload, {required WelcomeEmailStatus success}) async {
    if (_baseEndpoint.trim().isEmpty) return WelcomeEmailStatus.notConfigured;

    final base = Uri.tryParse(_baseEndpoint);
    final uri = base?.replace(path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return WelcomeEmailStatus.failed;
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
      await response.drain<void>();
      if (response.statusCode >= 200 && response.statusCode < 300) return success;
      if (response.statusCode == 400 && path == '/verify-email') return WelcomeEmailStatus.invalidCode;
      return WelcomeEmailStatus.failed;
    } on Object {
      return WelcomeEmailStatus.failed;
    } finally {
      client.close(force: true);
    }
  }
}
