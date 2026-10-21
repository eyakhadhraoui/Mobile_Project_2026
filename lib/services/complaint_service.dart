import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/complaint_model.dart';
import 'app_database.dart';

class ComplaintService {
  ComplaintService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  static final StreamController<String> _changes = StreamController.broadcast();
  final AppDatabase _database;

  Stream<List<ComplaintModel>> watchForUser(String userId) async* {
    yield await getForUser(userId);
    yield* _changes.stream
        .where(
          (changedUserId) => changedUserId == userId || changedUserId == '*',
        )
        .asyncMap((_) => getForUser(userId));
  }

  Stream<List<ComplaintModel>> watchAll() async* {
    yield await _getAll();
    yield* _changes.stream.asyncMap((_) => _getAll());
  }

  Future<List<ComplaintModel>> getForUser(String userId) async {
    final db = await _database.database;
    final rows = await db.query(
      'complaints',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'createdAt DESC',
    );
    return Future.wait(rows.map(_fromRow));
  }

  Future<List<ComplaintModel>> _getAll() async {
    final db = await _database.database;
    final rows = await db.query('complaints', orderBy: 'createdAt DESC');
    return Future.wait(rows.map(_fromRow));
  }

  Future<ComplaintModel?> getById(String complaintId) async {
    final db = await _database.database;
    final rows = await db.query(
      'complaints',
      where: 'id = ?',
      whereArgs: [complaintId],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<void> create(ComplaintModel complaint) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert('complaints', {
        'id': complaint.id,
        'userId': complaint.userId,
        'locationId': complaint.locationId.trim(),
        'subject': complaint.subject.trim(),
        'category': complaint.category.name,
        'description': complaint.description.trim(),
        'photos': jsonEncode(complaint.photos),
        'status': complaint.status.name,
        'priority': complaint.priority.name,
        'createdAt': complaint.createdAt.toUtc().toIso8601String(),
      });
      for (final entry in complaint.history) {
        await txn.insert('complaint_history', {
          'complaintId': complaint.id,
          'status': entry.status.name,
          'date': entry.date.toUtc().toIso8601String(),
        });
      }
      if (complaint.history.isEmpty) {
        await txn.insert('complaint_history', {
          'complaintId': complaint.id,
          'status': complaint.status.name,
          'date': complaint.createdAt.toUtc().toIso8601String(),
        });
      }
    });
    _changes.add('*');
  }

  Future<void> update(ComplaintModel complaint) async {
    final db = await _database.database;
    final previousRows = await db.query(
      'complaints',
      columns: ['photos'],
      where: 'id = ? AND userId = ?',
      whereArgs: [complaint.id, complaint.userId],
      limit: 1,
    );
    await db.transaction((txn) async {
      await txn.update(
        'complaints',
        {
          'locationId': complaint.locationId.trim(),
          'subject': complaint.subject.trim(),
          'category': complaint.category.name,
          'description': complaint.description.trim(),
          'photos': jsonEncode(complaint.photos),
          'priority': complaint.priority.name,
        },
        where: 'id = ? AND userId = ?',
        whereArgs: [complaint.id, complaint.userId],
      );
    });
    _changes.add('*');
    if (previousRows.isNotEmpty) {
      final removedPaths = List<String>.from(
        jsonDecode(previousRows.first['photos']! as String) as List,
      ).where((path) => !complaint.photos.contains(path));
      for (final path in removedPaths) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // A missing cached photo does not block complaint editing.
        }
      }
    }
  }

  Future<void> updateStatus(String complaintId, ComplaintStatus status) async {
    final db = await _database.database;
    final rows = await db.query(
      'complaints',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [complaintId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    if (rows.first['status'] == status.name) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'complaints',
        {'status': status.name},
        where: 'id = ?',
        whereArgs: [complaintId],
      );
      await txn.insert('complaint_history', {
        'complaintId': complaintId,
        'status': status.name,
        'date': now,
      });
    });
    _changes.add('*');
  }

  Future<void> delete(String complaintId, {required String userId}) async {
    final db = await _database.database;
    final rows = await db.query(
      'complaints',
      columns: ['photos'],
      where: 'id = ? AND userId = ?',
      whereArgs: [complaintId, userId],
      limit: 1,
    );
    await db.delete(
      'complaints',
      where: 'id = ? AND userId = ?',
      whereArgs: [complaintId, userId],
    );
    _changes.add('*');
    if (rows.isNotEmpty) {
      final paths = List<String>.from(
        jsonDecode(rows.first['photos']! as String) as List,
      );
      for (final path in paths) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // A missing cached photo does not block complaint deletion.
        }
      }
    }
  }

  Future<ComplaintModel> _fromRow(Map<String, Object?> row) async {
    final db = await _database.database;
    final historyRows = await db.query(
      'complaint_history',
      where: 'complaintId = ?',
      whereArgs: [row['id']],
      orderBy: 'date ASC',
    );
    return ComplaintModel(
      id: row['id']! as String,
      userId: row['userId']! as String,
      locationId: row['locationId']! as String,
      subject: row['subject']! as String,
      category: ComplaintCategory.values.firstWhere(
        (value) => value.name == row['category'],
        orElse: () => ComplaintCategory.autre,
      ),
      description: row['description']! as String,
      photos: List<String>.from(jsonDecode(row['photos']! as String) as List),
      status: ComplaintStatus.values.firstWhere(
        (value) => value.name == row['status'],
        orElse: () => ComplaintStatus.ouverte,
      ),
      createdAt: DateTime.parse(row['createdAt']! as String),
      priority: ComplaintPriority.values.firstWhere(
        (value) => value.name == row['priority'],
        orElse: () => ComplaintPriority.moyenne,
      ),
      history: historyRows
          .map(
            (entry) => ComplaintHistoryEntry(
              status: ComplaintStatus.values.firstWhere(
                (value) => value.name == entry['status'],
                orElse: () => ComplaintStatus.ouverte,
              ),
              date: DateTime.parse(entry['date']! as String),
            ),
          )
          .toList(),
    );
  }
}
