import 'dart:convert';

import '../models/annonce.dart';
import 'api_client.dart';
import 'database_helper.dart';
import 'photo_storage.dart';

class AnnoncesPage {
  const AnnoncesPage({
    required this.annonces,
    required this.meId,
    required this.meRole,
    this.moderation = false,
    this.etag,
  });
  final List<Annonce> annonces;
  final String meId;
  final String meRole;

  /// Vrai si le serveur exige une validation administrateur avant publication.
  final bool moderation;
  final String? etag;
}

/// Annonces partagées : toutes les opérations passent par le serveur.
class AnnonceService {
  AnnonceService({ApiClient? api, DatabaseHelper? databaseHelper, PhotoStorage? photoStorage})
    : _api = api ?? ApiClient(),
      _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
      _photoStorage = photoStorage ?? PhotoStorage();

  final ApiClient _api;
  final DatabaseHelper _databaseHelper;
  final PhotoStorage _photoStorage;

  /// Retourne null si rien n'a changé depuis [etag] (réponse 304).
  Future<AnnoncesPage?> lister({String? etag}) async {
    final response = await _api.send('GET', '/annonces', etag: etag);
    if (response.status == 304) return null;
    final data = Map<String, dynamic>.from(response.data as Map);
    final me = Map<String, dynamic>.from(data['me'] as Map);
    return AnnoncesPage(
      annonces: (data['items'] as List)
          .map((item) => Annonce.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      meId: me['id'] as String,
      meRole: me['role'] as String,
      moderation: me['moderation'] == true,
      etag: response.etag,
    );
  }

  Future<Annonce> ajouter(Annonce annonce) async {
    final payload = annonce.copyWith(photos: await _envoyerPhotos(annonce.photos)).toPayload();
    return _annonce(await _api.post('/annonces', payload));
  }

  Future<Annonce> modifier(Annonce annonce) async {
    final payload = annonce.copyWith(photos: await _envoyerPhotos(annonce.photos)).toPayload();
    return _annonce(await _api.put('/annonces/${annonce.id}', payload));
  }

  Future<void> supprimer(String id) => _api.delete('/annonces/$id');

  Future<Annonce> changerStatut(String id, StatutAnnonce statut, {String motif = ''}) async =>
      _annonce(await _api.post('/annonces/$id/statut', {'statut': statut.name, 'motif': motif}));

  /// Programme (ou reprogramme) la publication de l'annonce [id] à [date].
  /// L'annonce passe au statut « programmee » et devient invisible pour les autres.
  Future<Annonce> programmer(String id, DateTime date) async =>
      _annonce(await _api.post('/annonces/$id/programmation', {'datePublication': isoUtc(date)}));

  /// Annule la programmation : publication immédiate si [publierMaintenant]
  /// (ou envoi en validation si la modération est active), sinon « en attente ».
  Future<Annonce> annulerProgrammation(String id, {bool publierMaintenant = true}) async => _annonce(
    await _api.post('/annonces/$id/programmation', {'datePublication': null, 'publierMaintenant': publierMaintenant}),
  );

  Future<Annonce> noter(String id, int note) async => _annonce(await _api.post('/annonces/$id/avis', {'note': note}));

  Future<List<CommentaireAnnonce>> commentaires(String id) async => _commentaires(await _api.get('/annonces/$id/interactions'));

  Future<void> aimer(String id, bool aime) => _api.post('/annonces/$id/interactions', {'action': 'like', 'liked': aime});

  Future<List<CommentaireAnnonce>> commenter(String id, String texte) async =>
      _commentaires(await _api.post('/annonces/$id/interactions', {'action': 'comment', 'text': texte}));

  /// Envoie au serveur les annonces créées par [userId] avant la synchronisation
  /// (restées dans le SQLite de l'appareil), puis les retire de la base locale.
  /// Retourne le nombre d'annonces migrées.
  Future<int> migrerAnnoncesLocales(String userId) async {
    final db = await _databaseHelper.database;
    // cache_utilisateur NULL : vraie annonce locale (les autres lignes sont le cache hors ligne).
    final rows = await db.query(
      'annonces',
      where: 'proprietaireId = ? AND cache_utilisateur IS NULL',
      whereArgs: [userId],
    );
    var migrees = 0;
    for (final row in rows) {
      final anciennesPhotos = _decodeList(row['photos']);
      final ancienneCategorie = row['typeLocation'] as String? ?? '';
      final annonce = Annonce(
        id: row['id'] as String,
        categorie: Annonce.categories.contains(ancienneCategorie) && ancienneCategorie != 'Logement'
            ? ancienneCategorie
            : 'Autre',
        titre: (row['titre'] as String? ?? '').padRight(3, '.'),
        description: (row['description'] as String? ?? '').isEmpty ? '-' : row['description'] as String,
        photos: anciennesPhotos,
        proprietaireId: userId,
        autoriserCommentaires: row['autoriserCommentaires'] != 0,
      );
      final payload = annonce.copyWith(photos: await _envoyerPhotos(anciennesPhotos, ignorerManquantes: true)).toPayload()
        ..['legacyId'] = annonce.id;
      await _api.post('/annonces', payload);
      await db.delete('annonces', where: 'id = ?', whereArgs: [annonce.id]);
      for (final photo in anciennesPhotos) {
        await _photoStorage.supprimerSiInterne(photo);
      }
      migrees++;
    }
    return migrees;
  }

  Future<List<String>> _envoyerPhotos(List<String> photos, {bool ignorerManquantes = false}) async {
    final result = <String>[];
    for (final photo in photos.take(6)) {
      if (ApiClient.isRemotePhoto(photo)) {
        result.add(photo);
        continue;
      }
      try {
        result.add(await _api.uploadPhoto(photo));
      } on ApiException catch (error) {
        if (ignorerManquantes && error.code == 'photo_missing') continue;
        rethrow;
      }
    }
    return result;
  }

  Annonce _annonce(dynamic data) => Annonce.fromJson(Map<String, dynamic>.from(data as Map));

  List<CommentaireAnnonce> _commentaires(dynamic data) => ((data as Map)['comments'] as List? ?? const [])
      .map((item) => CommentaireAnnonce.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();

  List<String> _decodeList(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    return (jsonDecode(value) as List).cast<String>();
  }
}
