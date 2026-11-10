import 'package:sqflite/sqflite.dart';

import '../models/logement_loue.dart';
import 'database_helper.dart';
import 'housing_service.dart';

/// Date du jour au format AAAA-MM-JJ, comparable aux dates de location.
String jourCourant() => DateTime.now().toIso8601String().substring(0, 10);

/// Logements loués par un utilisateur. Le serveur fait foi ; la copie locale
/// permet de rester utilisable hors ligne.
class LogementLoueService {
  LogementLoueService({DatabaseHelper? database, HousingService? housing})
    : _database = database ?? DatabaseHelper.instance,
      _housing = housing ?? HousingService();

  final DatabaseHelper _database;
  final HousingService _housing;

  /// Remplace la copie locale par les locations acceptées et non échues.
  /// Lève une erreur si le serveur est injoignable : la copie reste intacte.
  Future<void> synchroniser(String userId) async {
    final demandes = (await _housing.demandesLocation()).envoyees;
    final aujourdHui = jourCourant();
    // Liste du plus récent au plus ancien : la dernière location d'un logement prime.
    final logements = <String, LogementLoue>{};
    for (final demande in demandes) {
      final fin = demande.data['endDate'] as String? ?? '';
      final annonceId = demande.data['propertyId'] as String? ?? '';
      if (demande.statut != 'accepted' ||
          annonceId.isEmpty ||
          fin.compareTo(aujourdHui) < 0) {
        continue;
      }
      logements.putIfAbsent(
        annonceId,
        () => LogementLoue(
          annonceId: annonceId,
          titre: demande.annonceTitre,
          adresse: demande.data['logementAdresse'] as String? ?? '',
          proprietaireId: demande.data['ownerId'] as String? ?? '',
          proprietaireNom: demande.proprietaireNom,
          debut: demande.data['startDate'] as String? ?? '',
          fin: fin,
        ),
      );
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        'logements_loues',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      for (final logement in logements.values) {
        await txn.insert(
          'logements_loues',
          logement.toJson(userId),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<LogementLoue>> lister(String userId) async {
    final db = await _database.database;
    final lignes = await db.query(
      'logements_loues',
      where: 'userId = ? AND fin >= ?',
      whereArgs: [userId, jourCourant()],
      orderBy: 'debut ASC, titre ASC',
    );
    return lignes.map(LogementLoue.fromJson).toList();
  }
}
