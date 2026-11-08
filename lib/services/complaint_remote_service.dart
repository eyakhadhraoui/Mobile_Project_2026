import 'dart:convert';
import 'dart:io';

import 'api_client.dart';

class ComplaintRemoteService {

  Future<List<Map<String, dynamic>>> fetchAll() async {
    final uri = _uri('/complaints');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(const Duration(seconds: 12));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) throw HttpException('Lecture refusée (${response.statusCode}).');
      final decoded = jsonDecode(body);
      if (decoded is! List) throw const FormatException('Réponse de réclamations invalide.');
      return decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> upload(Map<String, dynamic> complaint) async {
    final uri = _uri('/complaints');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(complaint));
      final response = await request.close().timeout(const Duration(seconds: 12));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw HttpException('Envoi refusé (${response.statusCode}) ${body.substring(0, body.length.clamp(0, 200))}');
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Envoie un message d'échange (création, modification ou suppression).
  /// Retourne false si le serveur ne connaît pas encore la réclamation
  /// (elle sera envoyée avant, à la prochaine synchronisation).
  Future<bool> uploadResponse(String complaintId, Map<String, dynamic> response) async {
    final uri = _uri('/complaints/${Uri.encodeComponent(complaintId)}/responses');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(response));
      final httpResponse = await request.close().timeout(const Duration(seconds: 12));
      await httpResponse.drain<void>();
      if (httpResponse.statusCode == 404) return false;
      if (httpResponse.statusCode != 200 && httpResponse.statusCode != 201) {
        throw HttpException('Envoi du message refusé (${httpResponse.statusCode}).');
      }
      return true;
    } finally {
      client.close(force: true);
    }
  }

  /// Même règle que le reste de l'application : HTTPS, ou http://10.0.2.2 en
  /// debug sur émulateur (ALLOW_INSECURE_MAIL_API=true).
  Uri _uri(String path) {
    final base = ApiClient.baseUri;
    if (base == null) throw const SocketException('URL API non configurée ou non sécurisée.');
    return base.replace(path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path');
  }
}
