import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/annonce.dart';
import 'database_helper.dart';

/// Copie hors ligne, dans la table SQLite `annonces`, des annonces renvoyées
/// par le serveur pour l'utilisateur connecté.
///
/// Les lignes du cache ont `cache_utilisateur` renseigné ; les lignes où il est
/// NULL sont d'anciennes annonces locales, en attente d'envoi au serveur, et ne
/// sont jamais touchées ici.
class AnnonceCacheService {
  AnnonceCacheService({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _databaseHelper;

  /// Base utilisée, partagée avec la file d'envoi.
  DatabaseHelper get databaseHelper => _databaseHelper;

  /// Remplace tout le cache par [annonces] (liste reçue pour [userId]).
  Future<void> remplacer(String userId, List<Annonce> annonces) async {
    final db = await _databaseHelper.database;
    await db.transaction((txn) async {
      await txn.delete('annonces', where: 'cache_utilisateur IS NOT NULL');
      for (final annonce in annonces) {
        await txn.insert('annonces', _ligne(userId, annonce), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Ajoute ou met à jour une annonce du cache.
  Future<void> enregistrer(String userId, Annonce annonce) async {
    final db = await _databaseHelper.database;
    await db.insert('annonces', _ligne(userId, annonce), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Annonces en cache pour [userId], de la plus récente à la plus ancienne.
  Future<List<Annonce>> lire(String userId) async {
    final db = await _databaseHelper.database;
    final rows = await db.query('annonces', where: 'cache_utilisateur = ?', whereArgs: [userId]);
    final annonces = rows.map(_annonce).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return annonces;
  }

  /// Annonces « programmee » dont la date de publication est passée à [maintenant].
  /// Les dates sont toutes stockées au même format ISO UTC : la comparaison de
  /// chaînes dans SQLite équivaut à une comparaison de dates.
  Future<List<Annonce>> programmeesEchues(String userId, DateTime maintenant) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'annonces',
      where: 'cache_utilisateur = ? AND statut = ? AND date_publication IS NOT NULL AND date_publication <= ?',
      whereArgs: [userId, StatutAnnonce.programmee.name, isoUtc(maintenant)],
      orderBy: 'date_publication',
    );
    return rows.map(_annonce).toList();
  }

  /// Vrai s'il reste au moins une annonce « programmee » pour [userId].
  Future<bool> aDesProgrammees(String userId) async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'annonces',
      columns: ['id'],
      where: 'cache_utilisateur = ? AND statut = ?',
      whereArgs: [userId, StatutAnnonce.programmee.name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Change le statut d'une annonce du cache (colonne et copie JSON).
  Future<void> changerStatut(String id, StatutAnnonce statut) async {
    final db = await _databaseHelper.database;
    final rows = await db.query('annonces', where: 'id = ? AND cache_utilisateur IS NOT NULL', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final annonce = _annonce(rows.first).copyWith(statut: statut);
    await db.update(
      'annonces',
      {'statut': statut.name, 'donnees': jsonEncode(annonce.toJson())},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> supprimer(String id) async {
    final db = await _databaseHelper.database;
    await db.delete('annonces', where: 'id = ? AND cache_utilisateur IS NOT NULL', whereArgs: [id]);
  }

  /// Vide le cache (déconnexion).
  Future<void> vider() async {
    final db = await _databaseHelper.database;
    await db.delete('annonces', where: 'cache_utilisateur IS NOT NULL');
  }

  /// Ligne SQLite : les colonnes historiques (NOT NULL) sont remplies pour rester
  /// compatibles avec l'ancien schéma ; `donnees` contient l'annonce complète.
  Map<String, Object?> _ligne(String userId, Annonce annonce) => {
    'id': annonce.id,
    'titre': annonce.titre,
    'description': annonce.description,
    'typeLocation': annonce.typeLocation,
    'loyer': annonce.loyer,
    'surface': annonce.surface,
    'chambres': annonce.chambres,
    'etage': annonce.etage,
    'ville': annonce.ville,
    'quartier': annonce.quartier,
    'adresse': annonce.adresse,
    'photos': jsonEncode(annonce.photos),
    'statut': annonce.statut.name,
    'proprietaireId': annonce.proprietaireId,
    'autoriserCommentaires': annonce.autoriserCommentaires ? 1 : 0,
    'categorie': annonce.categorie,
    'date_publication': annonce.datePublication == null ? null : isoUtc(annonce.datePublication!),
    'cache_utilisateur': userId,
    'donnees': jsonEncode(annonce.toJson()),
  };

  /// Les colonnes `statut` et `date_publication` font foi (le planificateur
  /// modifie la colonne `statut`).
  Annonce _annonce(Map<String, Object?> row) {
    final json = Map<String, dynamic>.from(jsonDecode(row['donnees'] as String? ?? '{}') as Map)
      ..['id'] = row['id']
      ..['proprietaireId'] = row['proprietaireId']
      ..['statut'] = row['statut']
      ..['datePublication'] = row['date_publication'];
    return Annonce.fromJson(json);
  }
}
