import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/photo_analysis.dart';

class GeminiException implements Exception {
  const GeminiException(this.message);

  /// Texte affichable tel quel à l'utilisateur.
  final String message;

  @override
  String toString() => message;
}

/// Analyse d'une photo par le serveur StudentHub. La clé Gemini reste sur le
/// serveur : l'application n'appelle jamais Google directement.
class GeminiService {
  GeminiService({http.Client? client, @visibleForTesting String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _urlConfiguree;

  static const _urlConfiguree = String.fromEnvironment('ACCOUNT_API_URL');
  static const _httpAutorise = bool.fromEnvironment('ALLOW_INSECURE_MAIL_API');
  static const _delai = Duration(seconds: 60);

  static const _impossible = GeminiException(
    'Analyse impossible. Réessaie ou remplis le formulaire à la main.',
  );
  static const _injoignable = GeminiException(
    'Serveur injoignable. Tu peux remplir le formulaire à la main.',
  );

  final http.Client _client;
  final String _baseUrl;

  Future<PhotoAnalysis> analyserPhoto(File photo) async {
    final uri = _adresse();
    final http.Response reponse;
    try {
      final image = await photo.readAsBytes();
      reponse = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'imageBase64': base64Encode(image),
              'mimeType': _typeImage(photo.path),
            }),
          )
          .timeout(_delai);
    } on FileSystemException {
      throw _impossible;
    } on SocketException {
      throw _injoignable;
    } on TimeoutException {
      throw _injoignable;
    } on http.ClientException {
      throw _injoignable;
    } on HttpException {
      throw _injoignable;
    } on HandshakeException {
      throw _injoignable;
    }
    return _lire(reponse);
  }

  Uri _adresse() {
    final base = _baseUrl.trim();
    if (base.isEmpty) {
      throw const GeminiException(
        'Analyse IA non configurée. Remplis le formulaire à la main.',
      );
    }
    final uri = Uri.tryParse(base);
    final emulateur =
        kDebugMode &&
        _httpAutorise &&
        uri?.scheme == 'http' &&
        uri?.host == '10.0.2.2';
    if (uri == null || uri.host.isEmpty || (uri.scheme != 'https' && !emulateur)) {
      throw const GeminiException(
        'Adresse du serveur invalide. Remplis le formulaire à la main.',
      );
    }
    final chemin = uri.path.replaceFirst(RegExp(r'/$'), '');
    return uri.replace(path: '$chemin/maintenance/analyze');
  }

  String _typeImage(String chemin) => switch (p.extension(chemin).toLowerCase()) {
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    _ => 'image/jpeg',
  };

  PhotoAnalysis _lire(http.Response reponse) {
    switch (reponse.statusCode) {
      case 200:
        break;
      case 413:
        throw const GeminiException(
          'Photo trop lourde. Choisis une image plus légère.',
        );
      case 415:
        throw const GeminiException(
          'Format non pris en charge. Utilise une photo JPEG, PNG ou WebP.',
        );
      case 429:
        throw const GeminiException(
          "Trop d'analyses pour le moment. Réessaie plus tard.",
        );
      case 503:
        throw const GeminiException(
          'Analyse IA non configurée sur le serveur. Remplis le formulaire à la main.',
        );
      default:
        throw _impossible;
    }
    try {
      final data = jsonDecode(utf8.decode(reponse.bodyBytes));
      if (data is Map<String, dynamic>) return PhotoAnalysis.fromJson(data);
    } on FormatException {
      throw _impossible;
    }
    throw _impossible;
  }

  void fermer() => _client.close();
}
