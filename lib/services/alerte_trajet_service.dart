import 'package:sqflite/sqflite.dart';

import '../models/alerte_trajet.dart';
import 'database_helper.dart';

class AlerteTrajetService {
  AlerteTrajetService({DatabaseHelper? database})
    : _db = database ?? DatabaseHelper.instance;
  final DatabaseHelper _db;
  Future<List<AlerteTrajet>> pourUtilisateur(String id) async {
    final db = await _db.database;
    return (await db.query(
      'alertes_trajet',
      where: 'userId = ?',
      whereArgs: [id],
      orderBy: 'dateCreation DESC',
    )).map(AlerteTrajet.fromMap).toList();
  }

  Future<List<AlerteTrajet>> activesZone(String zone) async {
    final db = await _db.database;
    return (await db.query(
      'alertes_trajet',
      where: 'zone = ? AND active = 1',
      whereArgs: [zone],
    )).map(AlerteTrajet.fromMap).toList();
  }

  Future<void> enregistrer(AlerteTrajet a) async {
    final db = await _db.database;
    await db.insert(
      'alertes_trajet',
      a.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> supprimer(String id) async {
    final db = await _db.database;
    await db.delete('alertes_trajet', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> actif(String id, bool v) async {
    final db = await _db.database;
    await db.update(
      'alertes_trajet',
      {'active': v ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
