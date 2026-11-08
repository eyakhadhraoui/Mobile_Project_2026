import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AiChatService {
  const AiChatService();

  static const _baseEndpoint = String.fromEnvironment(
    'ACCOUNT_API_URL',
    defaultValue: '',
  );
  static const _allowEmulatorHttp = bool.fromEnvironment(
    'ALLOW_INSECURE_MAIL_API',
    defaultValue: false,
  );

  Future<String> send(List<Map<String, String>> messages) async {
    if (_baseEndpoint.trim().isEmpty) {
      throw const AiChatException(
        'Configurez ACCOUNT_API_URL pour joindre le serveur.',
      );
    }
    final base = Uri.tryParse(_baseEndpoint);
    final uri = base?.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/chat',
    );
    final localEmulator =
        kDebugMode &&
        _allowEmulatorHttp &&
        uri?.scheme == 'http' &&
        uri?.host == '10.0.2.2';
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !localEmulator)) {
      throw const AiChatException(
        'URL serveur invalide. En émulateur, utilisez http://10.0.2.2:6500.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode({'messages': messages}));
      final response = await request.close().timeout(
        const Duration(seconds: 50),
      );
      final payload = jsonDecode(await response.transform(utf8.decoder).join());
      if (response.statusCode == 200 &&
          payload is Map &&
          payload['reply'] is String) {
        return payload['reply'] as String;
      }
      if (response.statusCode == 503) {
        throw const AiChatException(
          'Assistant non configuré : ajoutez OPENAI_API_KEY dans backend/.env.',
        );
      }
      throw const AiChatException(
        'Le service IA est indisponible. Réessayez plus tard.',
      );
    } on AiChatException {
      rethrow;
    } on Object {
      throw const AiChatException(
        'Serveur injoignable. Vérifiez qu’il est démarré.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

class AiChatException implements Exception {
  const AiChatException(this.message);
  final String message;
  @override
  String toString() => message;
}
