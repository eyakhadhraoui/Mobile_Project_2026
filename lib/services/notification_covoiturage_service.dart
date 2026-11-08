import 'package:sqflite/sqflite.dart';
import '../models/notification_covoiturage.dart';
import '../models/enums_covoiturage.dart';
import 'database_helper.dart';

class NotificationCovoiturageService {
  NotificationCovoiturageService({DatabaseHelper? database}) : _database = database ?? DatabaseHelper.instance;
  final DatabaseHelper _database;
  String _id() => 'n_${DateTime.now().microsecondsSinceEpoch}';
  Future<void> creer({required String userId, required TypeNotificationEnum type, required String titre, required String message, String? trajetId, String? reservationId, String? cleUnique}) async {
    final db = await _database.database;
    try { await db.insert('covoiturage_notifications', NotificationCovoiturage(id: _id(), userId: userId, type: type, titre: titre, message: message, trajetId: trajetId, reservationId: reservationId, dateCreation: DateTime.now().toIso8601String(), cleUnique: cleUnique).toMap(), conflictAlgorithm: ConflictAlgorithm.ignore); } on DatabaseException { rethrow; }
  }
  Future<List<NotificationCovoiturage>> pourUtilisateur(String userId) async { final db = await _database.database; final rows = await db.query('covoiturage_notifications', where: 'userId = ?', whereArgs: [userId], orderBy: 'dateCreation DESC'); return rows.map(NotificationCovoiturage.fromMap).toList(); }
  Future<int> nonLues(String userId) async { final db = await _database.database; return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM covoiturage_notifications WHERE userId = ? AND lue = 0', [userId])) ?? 0; }
  Future<void> lire(String id) async { final db = await _database.database; await db.update('covoiturage_notifications', {'lue': 1}, where: 'id = ?', whereArgs: [id]); }
  Future<void> toutLire(String userId) async { final db = await _database.database; await db.update('covoiturage_notifications', {'lue': 1}, where: 'userId = ?', whereArgs: [userId]); }
}
