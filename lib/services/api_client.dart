import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Erreur renvoyée par l'API StudentHub, avec un message prêt à afficher.
class ApiException implements Exception {
  const ApiException(this.message, {this.status, this.code = 'error'});

  final String message;

  /// Code HTTP, ou null si le serveur n'a pas pu être joint.
  final int? status;
  final String code;

  bool get isNetwork => status == null;

  /// Le serveur ne peut pas être joint, ou la session a été ouverte sans lui :
  /// l'action peut attendre le retour de la connexion.
  bool get horsConnexion => code == 'network' || code == 'no_session';

  @override
  String toString() => message;
}

class ApiResponse {
  const ApiResponse(this.status, this.data, this.etag);
  final int status;
  final dynamic data;
  final String? etag;
}

/// Client HTTP unique pour le serveur Node : URL, jeton de session et erreurs.
class ApiClient {
  ApiClient({AppDatabase? database}) : _database = database ?? AppDatabase.instance;

  static const tokenKey = 'apiToken';
  /// En debug Android, `10.0.2.2` désigne le localhost de l'ordinateur hôte.
  /// Une URL explicite reste prioritaire pour les autres environnements.
  static const _baseUrl = String.fromEnvironment(
    'ACCOUNT_API_URL',
    defaultValue: 'http://10.0.2.2:6500',
  );
  static const _allowEmulatorHttp = bool.fromEnvironment(
    'ALLOW_INSECURE_MAIL_API',
    defaultValue: true,
  );

  final AppDatabase _database;

  /// Signale un compte bloqué ou en attente, pour fermer la session en cours.
  static final _compteRefuse = StreamController<String>.broadcast();
  static Stream<String> get compteRefuse => _compteRefuse.stream;

  /// URL de base validée (HTTPS, ou HTTP vers l'émulateur Android en debug).
  static Uri? get baseUri {
    if (_baseUrl.trim().isEmpty) return null;
    final base = Uri.tryParse(_baseUrl.trim());
    if (base == null || base.host.isEmpty) return null;
    final emulatorHttp = kDebugMode && _allowEmulatorHttp && base.scheme == 'http' && base.host == '10.0.2.2';
    if (base.scheme != 'https' && !emulatorHttp) return null;
    return base;
  }

  static Uri _uri(String path) {
    final base = baseUri;
    if (base == null) {
      throw ApiException(
        _baseUrl.trim().isEmpty
            ? 'Serveur non configuré : lancez l’application avec ACCOUNT_API_URL.'
            : 'ACCOUNT_API_URL invalide (HTTPS requis, ou http://10.0.2.2 en debug).',
        code: 'not_configured',
      );
    }
    final uri = Uri.parse(path);
    return base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}${uri.path}',
      query: uri.hasQuery ? uri.query : null,
    );
  }

  /// Les photos d'annonces sont stockées par le serveur sous `/photos/...`.
  static bool isRemotePhoto(String path) => path.startsWith('/photos/');

  static String photoUrl(String path) {
    if (!isRemotePhoto(path) || baseUri == null) return path;
    return _uri(path).toString();
  }

  Future<String?> token() async {
    final db = await _database.database;
    final rows = await db.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: [tokenKey], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> saveToken(String? value) async {
    final db = await _database.database;
    if (value == null) {
      await db.delete('app_settings', where: 'key = ?', whereArgs: [tokenKey]);
    } else {
      await db.insert('app_settings', {'key': tokenKey, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<dynamic> get(String path) async => (await send('GET', path)).data;

  /// GET dont la dernière réponse reste lisible sans connexion, pour le compte
  /// connecté. La copie est rangée dans `app_settings`.
  Future<dynamic> getAvecCache(String path) async {
    final cle = await _cleCache(path);
    try {
      final data = await get(path);
      if (cle != null) await _ecrireCache(cle, data);
      return data;
    } on ApiException catch (error) {
      if (!error.horsConnexion || cle == null) rethrow;
      final copie = await _lireCache(cle);
      if (copie == null) rethrow;
      return jsonDecode(copie);
    }
  }

  /// Préfixe des copies de réponses d'un compte, à effacer avec lui.
  static String prefixeCache(String userId) => 'cache:$userId:';

  Future<String?> _cleCache(String path) async {
    try {
      final db = await _database.database;
      final rows = await db.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: ['currentUserId'], limit: 1);
      return rows.isEmpty ? null : '${prefixeCache(rows.first['value'] as String)}$path';
    } on Object catch (error) {
      debugPrint('Cache des réponses indisponible : $error');
      return null;
    }
  }

  Future<void> _ecrireCache(String cle, Object? data) async {
    try {
      final db = await _database.database;
      await db.insert('app_settings', {'key': cle, 'value': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
    } on Object catch (error) {
      debugPrint('Copie de la réponse impossible : $error');
    }
  }

  Future<String?> _lireCache(String cle) async {
    final db = await _database.database;
    final rows = await db.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: [cle], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// GET conditionnel pour un suivi régulier : la copie hors ligne n'est
  /// réécrite que lorsque la réponse a changé.
  Future<ApiResponse> getSiModifie(String path, String? etag) async {
    final reponse = await send('GET', path, etag: etag);
    if (reponse.status != 304) {
      final cle = await _cleCache(path);
      if (cle != null) await _ecrireCache(cle, reponse.data);
    }
    return reponse;
  }

  Future<dynamic> post(String path, [Object? body]) async => (await send('POST', path, body: body ?? const {})).data;
  Future<dynamic> put(String path, Object body) async => (await send('PUT', path, body: body)).data;
  Future<dynamic> delete(String path) async => (await send('DELETE', path)).data;

  Future<ApiResponse> send(
    String method,
    String path, {
    Object? body,
    String? etag,
    bool authenticated = true,
    List<int>? bytes,
  }) async {
    final uri = _uri(path);
    String? bearer;
    if (authenticated) {
      bearer = await token();
      if (bearer == null) {
        throw const ApiException(
          'Session serveur absente : déconnectez-vous puis reconnectez-vous avec le serveur démarré.',
          status: 401,
          code: 'no_session',
        );
      }
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.openUrl(method, uri).timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearer != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      if (etag != null) request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      if (bytes != null) {
        request.headers.contentType = ContentType('application', 'octet-stream');
        request.contentLength = bytes.length;
        request.add(bytes);
      } else if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds: 30));
      final text = await response.transform(utf8.decoder).join();
      final data = text.isEmpty ? null : jsonDecode(text);
      if (response.statusCode == 304 || (response.statusCode >= 200 && response.statusCode < 300)) {
        return ApiResponse(response.statusCode, data, response.headers.value(HttpHeaders.etagHeader));
      }
      final map = data is Map ? data : const {};
      final code = map['error'] as String? ?? 'error';
      if (response.statusCode == 403 && code.startsWith('account_')) _compteRefuse.add(code);
      throw ApiException(
        map['message'] as String? ?? 'Erreur du serveur (${response.statusCode}).',
        status: response.statusCode,
        code: code,
      );
    } on ApiException {
      rethrow;
    } on FormatException {
      throw const ApiException('Réponse du serveur illisible.', status: 502, code: 'bad_response');
    } on Object {
      throw const ApiException('Serveur injoignable : vérifiez la connexion et que le serveur Node est lancé.', code: 'network');
    } finally {
      client.close(force: true);
    }
  }

  /// Envoie une photo locale et retourne son chemin serveur (`/photos/...`).
  Future<String> uploadPhoto(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw ApiException('Photo introuvable : $filePath', code: 'photo_missing');
    final bytes = await file.readAsBytes();
    if (bytes.length > 6 * 1024 * 1024) throw const ApiException('Photo trop lourde (6 Mo maximum).', code: 'too_large');
    final response = await send('POST', '/photos', bytes: bytes);
    return (response.data as Map)['path'] as String;
  }
}
