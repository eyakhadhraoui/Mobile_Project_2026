import 'package:sqflite/sqflite.dart';
import '../models/evaluation_trajet.dart';
import 'database_helper.dart';
class Reputation { const Reputation(this.moyenne, this.nombre); final double? moyenne; final int nombre; }
class EvaluationService {
  EvaluationService({DatabaseHelper? database}) : _database = database ?? DatabaseHelper.instance;
  final DatabaseHelper _database;
  Future<void> creer(EvaluationTrajet evaluation) async { if (evaluation.note < 1 || evaluation.note > 5) throw ArgumentError('La note doit être comprise entre 1 et 5.'); final db = await _database.database; await db.insert('covoiturage_evaluations', evaluation.toMap(), conflictAlgorithm: ConflictAlgorithm.abort); }
  Future<bool> existe(String trajetId, String evaluateurId, String evalueId) async { final db = await _database.database; return (await db.query('covoiturage_evaluations', where: 'trajetId = ? AND evaluateurId = ? AND evalueId = ?', whereArgs: [trajetId, evaluateurId, evalueId], limit: 1)).isNotEmpty; }
  Future<Reputation> reputation(String userId) async { final db = await _database.database; final row = (await db.rawQuery('SELECT AVG(note) moyenne, COUNT(*) nombre FROM covoiturage_evaluations WHERE evalueId = ?', [userId])).first; return Reputation((row['moyenne'] as num?)?.toDouble(), (row['nombre'] as int?) ?? 0); }
  Future<List<EvaluationTrajet>> recues(String userId) async { final db = await _database.database; final rows = await db.query('covoiturage_evaluations', where: 'evalueId = ?', whereArgs: [userId], orderBy: 'dateCreation DESC'); return rows.map(EvaluationTrajet.fromMap).toList(); }
}
