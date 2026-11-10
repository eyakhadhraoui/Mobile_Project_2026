import 'dart:convert';
import 'dart:math';

import '../models/messagerie.dart';
import 'api_client.dart';
import 'database_helper.dart';
import 'photo_storage.dart';

/// Échanges avec le serveur, et file durable (table `messages_file`) des
/// messages écrits sans connexion : elle survit à la fermeture de l'application.
class MessagerieService {
  MessagerieService({ApiClient? client, DatabaseHelper? databaseHelper, PhotoStorage? stockage})
    : _client = client ?? ApiClient(),
      _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
      _stockage = stockage ?? PhotoStorage();

  final ApiClient _client;
  final DatabaseHelper _databaseHelper;
  final PhotoStorage _stockage;

  /// Un seul envoi à la fois, même si la liste et la discussion le demandent ensemble.
  static Future<void> _envoiEnCours = Future<void>.value();
  static final _hasard = Random();

  static List<MessageDiscussion> _lireFil(dynamic data) => [
    for (final message in (data as Map)['messages'] as List)
      MessageDiscussion.fromJson(Map<String, dynamic>.from(message as Map)),
  ];

  Future<List<ConversationResume>> conversations() async {
    final data = await _client.getAvecCache('/conversations') as List;
    return [
      for (final item in data) ConversationResume.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  /// Retrouve ou crée la conversation sur une annonce. [locataireId] n'est
  /// fourni que lorsque le propriétaire écrit le premier.
  Future<ConversationResume> ouvrir({required String annonceId, String? locataireId}) async {
    final data = await _client.post('/conversations', {
      'annonceId': annonceId,
      'locataireId': ?locataireId,
    });
    return ConversationResume.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Première lecture : la dernière copie reste lisible sans connexion.
  Future<PageMessages> messages(String conversationId) async =>
      PageMessages(_lireFil(await _client.getAvecCache('/conversations/$conversationId/messages')), null);

  /// Suivi régulier ; retourne null quand rien n'a changé.
  Future<PageMessages?> nouveautes(String conversationId, {String? etag}) async {
    final reponse = await _client.getSiModifie('/conversations/$conversationId/messages', etag);
    if (reponse.status == 304) return null;
    return PageMessages(_lireFil(reponse.data), reponse.etag);
  }

  // ---------------------------------------------------------------------------
  // File d'envoi
  // ---------------------------------------------------------------------------

  /// Enregistre le message et ses photos sur le téléphone avant tout envoi.
  Future<void> mettreEnFile({
    required String userId,
    required String conversationId,
    required String texte,
    required List<String> photos,
    required String langue,
  }) async {
    final copies = await _stockage.copierPhotos(photos);
    final db = await _databaseHelper.database;
    final now = DateTime.now();
    await db.insert('messages_file', {
      'clientId': '${now.microsecondsSinceEpoch.toRadixString(36)}${_hasard.nextInt(1 << 32).toRadixString(36)}',
      'userId': userId,
      'conversationId': conversationId,
      'texte': texte,
      'photos': jsonEncode(copies),
      'langue': langue,
      'etat': 'attente',
      'createdAt': now.toUtc().toIso8601String(),
    });
  }

  Future<List<MessageDiscussion>> enAttente(String userId, String conversationId) async {
    final db = await _databaseHelper.database;
    final lignes = await db.query(
      'messages_file',
      where: 'userId = ? AND conversationId = ?',
      whereArgs: [userId, conversationId],
      orderBy: 'createdAt',
    );
    return [
      for (final ligne in lignes)
        MessageDiscussion(
          id: ligne['clientId']! as String,
          clientId: ligne['clientId']! as String,
          auteurId: userId,
          texte: ligne['texte']! as String,
          photos: _photos(ligne),
          langue: ligne['langue']! as String,
          date: DateTime.parse(ligne['createdAt']! as String).toLocal(),
          etat: ligne['etat'] == 'echec' ? EtatEnvoi.echec : EtatEnvoi.enAttente,
          erreur: ligne['erreur'] as String?,
        ),
    ];
  }

  static List<String> _photos(Map<String, Object?> ligne) =>
      [for (final photo in jsonDecode(ligne['photos']! as String) as List) photo as String];

  /// Envoie les messages en attente, dans l'ordre. Une coupure interrompt
  /// l'envoi (l'exception est relancée) ; un refus du serveur ne bloque que ce message.
  Future<void> envoyerFile(String userId, {String? conversationId}) {
    final suite = _envoiEnCours.catchError((Object _) {}).then((_) => _envoyer(userId, conversationId));
    _envoiEnCours = suite;
    return suite;
  }

  Future<void> _envoyer(String userId, String? conversationId) async {
    final db = await _databaseHelper.database;
    final lignes = await db.query(
      'messages_file',
      where: conversationId == null ? "userId = ? AND etat = 'attente'" : "userId = ? AND etat = 'attente' AND conversationId = ?",
      whereArgs: [userId, ?conversationId],
      orderBy: 'createdAt',
    );
    for (final ligne in lignes) {
      final clientId = ligne['clientId']! as String;
      try {
        final photos = _photos(ligne);
        for (var i = 0; i < photos.length; i++) {
          if (ApiClient.isRemotePhoto(photos[i])) continue;
          final locale = photos[i];
          photos[i] = await _client.uploadPhoto(locale);
          // Noté aussitôt : une coupure ensuite ne renverra pas cette photo.
          await db.update('messages_file', {'photos': jsonEncode(photos)}, where: 'clientId = ?', whereArgs: [clientId]);
          await _stockage.supprimerSiInterne(locale);
        }
        await _client.post('/conversations/${ligne['conversationId']}/messages', {
          'clientId': clientId,
          'texte': ligne['texte'],
          'photos': photos,
          'langue': ligne['langue'],
        });
        await db.delete('messages_file', where: 'clientId = ?', whereArgs: [clientId]);
      } on ApiException catch (erreur) {
        if (!_refusDefinitif(erreur)) rethrow;
        await db.update(
          'messages_file',
          {'etat': 'echec', 'erreur': erreur.message},
          where: 'clientId = ?',
          whereArgs: [clientId],
        );
      }
    }
  }

  /// Refus propre à ce message : réessayer tel quel ne changerait rien. Une
  /// session expirée ou un serveur en panne laissent le message en attente.
  static bool _refusDefinitif(ApiException erreur) {
    if (erreur.code == 'photo_missing' || erreur.code == 'too_large') return true;
    final status = erreur.status;
    return status != null && status >= 400 && status < 500 && status != 401 && !erreur.code.startsWith('account_');
  }

  Future<void> reessayer(String clientId) async {
    final db = await _databaseHelper.database;
    await db.update('messages_file', {'etat': 'attente', 'erreur': null}, where: 'clientId = ?', whereArgs: [clientId]);
  }

  /// Abandonne un message non envoyé et efface ses photos du téléphone.
  Future<void> abandonner(String clientId) async {
    final db = await _databaseHelper.database;
    final lignes = await db.query('messages_file', where: 'clientId = ?', whereArgs: [clientId], limit: 1);
    if (lignes.isEmpty) return;
    await db.delete('messages_file', where: 'clientId = ?', whereArgs: [clientId]);
    for (final photo in _photos(lignes.first)) {
      await _stockage.supprimerSiInterne(photo);
    }
  }
}
