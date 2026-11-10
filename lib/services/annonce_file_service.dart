import 'dart:convert';

import 'database_helper.dart';

enum TypeOperationAnnonce { ajouter, modifier, supprimer, aimer, noter, commenter }

/// Action faite sans connexion, en attente d'envoi au serveur.
class OperationAnnonce {
  const OperationAnnonce({
    required this.id,
    required this.type,
    required this.annonceId,
    required this.donnees,
  });

  final int id;
  final TypeOperationAnnonce type;
  final String annonceId;
  final Map<String, dynamic> donnees;

  OperationAnnonce avecDonnees(Map<String, dynamic> nouvelles) => OperationAnnonce(
    id: id,
    type: type,
    annonceId: annonceId,
    donnees: nouvelles,
  );
}

/// File durable (table `annonces_file`) : elle survit à la fermeture de l'application.
class AnnonceFileService {
  AnnonceFileService({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _databaseHelper;

  Future<List<OperationAnnonce>> lister(String userId) async {
    final db = await _databaseHelper.database;
    final lignes = await db.query(
      'annonces_file',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'id',
    );
    return [
      for (final ligne in lignes)
        OperationAnnonce(
          id: ligne['id']! as int,
          type: TypeOperationAnnonce.values.byName(ligne['type']! as String),
          annonceId: ligne['annonceId']! as String,
          donnees: Map<String, dynamic>.from(jsonDecode(ligne['donnees']! as String) as Map),
        ),
    ];
  }

  Future<OperationAnnonce> ajouter(
    String userId,
    TypeOperationAnnonce type,
    String annonceId,
    Map<String, dynamic> donnees,
  ) async {
    final db = await _databaseHelper.database;
    final id = await db.insert('annonces_file', {
      'userId': userId,
      'type': type.name,
      'annonceId': annonceId,
      'donnees': jsonEncode(donnees),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    return OperationAnnonce(id: id, type: type, annonceId: annonceId, donnees: donnees);
  }

  Future<void> remplacerDonnees(int id, Map<String, dynamic> donnees) async {
    final db = await _databaseHelper.database;
    await db.update('annonces_file', {'donnees': jsonEncode(donnees)}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> retirer(int id) async {
    final db = await _databaseHelper.database;
    await db.delete('annonces_file', where: 'id = ?', whereArgs: [id]);
  }
}
