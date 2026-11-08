import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../core/constants/langues.dart';
import '../models/complaint_model.dart';
import '../models/complaint_response_model.dart';
import 'app_database.dart';
import 'complaint_remote_service.dart';

class ComplaintService {
  ComplaintService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  static final StreamController<String> _changes = StreamController.broadcast();
  final AppDatabase _database;
  final ComplaintRemoteService _remote = ComplaintRemoteService();
  bool _syncing = false;

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
      where: 'userId = ? AND isDeleted = 0',
      whereArgs: [userId],
      orderBy: 'createdAt DESC',
    );
    return Future.wait(rows.map(_fromRow));
  }

  Future<List<ComplaintModel>> _getAll() async {
    final db = await _database.database;
    final rows = await db.query('complaints', where: 'isDeleted = 0', orderBy: 'createdAt DESC');
    return Future.wait(rows.map(_fromRow));
  }

  // ---------------------------------------------------------------------------
  // Échanges (réponses du propriétaire et messages de l'étudiant)
  // ---------------------------------------------------------------------------

  /// Messages d'une réclamation, mis à jour à chaque modification ou synchronisation.
  Stream<List<ComplaintResponse>> watchResponses(String complaintId) async* {
    yield await getResponses(complaintId);
    yield* _changes.stream.asyncMap((_) => getResponses(complaintId));
  }

  Future<List<ComplaintResponse>> getResponses(String complaintId) async {
    final db = await _database.database;
    final rows = await db.query(
      'complaint_responses',
      where: 'complaintId = ? AND isDeleted = 0',
      whereArgs: [complaintId],
      orderBy: 'createdAt ASC',
    );
    return rows.map(_responseFromRow).toList();
  }

  /// Ajoute un message (enregistré hors ligne, envoyé à la prochaine synchronisation).
  Future<ComplaintResponse> addResponse({
    required String complaintId,
    required String authorId,
    required ComplaintAuthorRole authorRole,
    required String text,
    required String langue,
  }) async {
    final now = DateTime.now().toUtc();
    final response = ComplaintResponse(
      id: '${now.microsecondsSinceEpoch}_${authorId.hashCode.toUnsigned(20)}',
      complaintId: complaintId,
      authorId: authorId,
      authorRole: authorRole,
      text: text.trim(),
      langue: langueValide(langue),
      createdAt: now,
    );
    final db = await _database.database;
    await db.insert('complaint_responses', _responseToRow(response));
    _changes.add('*');
    return response;
  }

  /// Modifie le texte d'un message de [authorId]. Ses traductions en cache sont
  /// supprimées : elles ne correspondent plus au texte.
  Future<void> updateResponse(String responseId, String text, {required String authorId}) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final count = await txn.update(
        'complaint_responses',
        {
          'text': text.trim(),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'syncStatus': ComplaintSyncStatus.pending.name,
        },
        where: 'id = ? AND authorId = ?',
        whereArgs: [responseId, authorId],
      );
      if (count > 0) await _supprimerTraductions(txn, responseId);
    });
    _changes.add('*');
  }

  /// Supprime un message de [authorId] (suppression envoyée au serveur) et ses traductions.
  Future<void> deleteResponse(String responseId, {required String authorId}) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final count = await txn.update(
        'complaint_responses',
        {
          'isDeleted': 1,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'syncStatus': ComplaintSyncStatus.pending.name,
        },
        where: 'id = ? AND authorId = ?',
        whereArgs: [responseId, authorId],
      );
      if (count > 0) await _supprimerTraductions(txn, responseId);
    });
    _changes.add('*');
  }

  /// Cache des traductions (table `traductions`) d'un message.
  Future<void> _supprimerTraductions(DatabaseExecutor db, String responseId) =>
      db.delete('traductions', where: 'reponse_id = ?', whereArgs: [responseId]);

  Map<String, Object?> _responseToRow(ComplaintResponse item) => {
    'id': item.id,
    'complaintId': item.complaintId,
    'authorId': item.authorId,
    'authorRole': item.authorRole.name,
    'text': item.text,
    'langue': item.langue,
    'createdAt': item.createdAt.toUtc().toIso8601String(),
    'updatedAt': item.updatedAt?.toUtc().toIso8601String(),
    'syncStatus': item.syncStatus.name,
    'isDeleted': item.isDeleted ? 1 : 0,
  };

  ComplaintResponse _responseFromRow(Map<String, Object?> row) => ComplaintResponse(
    id: row['id']! as String,
    complaintId: row['complaintId']! as String,
    authorId: row['authorId']! as String,
    authorRole: ComplaintAuthorRole.values.firstWhere(
      (value) => value.name == row['authorRole'],
      orElse: () => ComplaintAuthorRole.etudiant,
    ),
    text: row['text']! as String,
    langue: langueValide(row['langue']),
    createdAt: DateTime.parse(row['createdAt']! as String),
    updatedAt: row['updatedAt'] == null ? null : DateTime.tryParse(row['updatedAt']! as String),
    syncStatus: ComplaintSyncStatus.values.firstWhere(
      (value) => value.name == row['syncStatus'],
      orElse: () => ComplaintSyncStatus.pending,
    ),
    isDeleted: (row['isDeleted'] as int? ?? 0) == 1,
  );

  /// Fusionne les messages reçus du serveur pour une réclamation. Un message
  /// local non encore envoyé est prioritaire. Si le texte a changé (ou si le
  /// message a été supprimé), ses traductions en cache sont effacées.
  Future<bool> _saveRemoteResponses(Database db, String complaintId, Object? remote) async {
    if (remote is! List) return false;
    var changed = false;
    for (final entry in remote) {
      if (entry is! Map) continue;
      final value = Map<String, dynamic>.from(entry);
      final id = value['id'];
      final text = value['text'];
      if (id is! String || text is! String || value['createdAt'] is! String) continue;
      final local = await db.query(
        'complaint_responses',
        columns: ['text', 'syncStatus'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (local.isNotEmpty && local.first['syncStatus'] == ComplaintSyncStatus.pending.name) continue;
      if (value['deleted'] == true) {
        if (local.isNotEmpty) {
          await db.delete('complaint_responses', where: 'id = ?', whereArgs: [id]);
          await _supprimerTraductions(db, id);
          changed = true;
        }
        continue;
      }
      if (local.isNotEmpty && local.first['text'] == text) continue;
      if (local.isNotEmpty) await _supprimerTraductions(db, id);
      await db.insert('complaint_responses', {
        'id': id,
        'complaintId': complaintId,
        'authorId': value['authorId'] is String ? value['authorId'] : '',
        'authorRole': value['authorRole'] == ComplaintAuthorRole.proprietaire.name
            ? ComplaintAuthorRole.proprietaire.name
            : ComplaintAuthorRole.etudiant.name,
        'text': text,
        'langue': langueValide(value['langue']),
        'createdAt': value['createdAt'],
        'updatedAt': value['updatedAt'] is String ? value['updatedAt'] : null,
        'syncStatus': ComplaintSyncStatus.synced.name,
        'isDeleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      changed = true;
    }
    return changed;
  }

  /// Envoie les messages en attente. Un message dont la réclamation n'est pas
  /// encore connue du serveur reste en attente.
  Future<bool> _uploadPendingResponses(Database db) async {
    var changed = false;
    final pending = await db.query(
      'complaint_responses',
      where: 'syncStatus = ?',
      whereArgs: [ComplaintSyncStatus.pending.name],
      orderBy: 'createdAt ASC',
    );
    for (final row in pending) {
      final item = _responseFromRow(row);
      final accepted = await _remote.uploadResponse(item.complaintId, {
        'id': item.id,
        'authorId': item.authorId,
        'authorRole': item.authorRole.name,
        'text': item.text,
        'langue': item.langue,
        'createdAt': item.createdAt.toUtc().toIso8601String(),
        'updatedAt': item.updatedAt?.toUtc().toIso8601String(),
        'deleted': item.isDeleted,
      });
      if (!accepted) continue;
      if (item.isDeleted) {
        await db.delete('complaint_responses', where: 'id = ?', whereArgs: [item.id]);
      } else {
        await db.update(
          'complaint_responses',
          {'syncStatus': ComplaintSyncStatus.synced.name},
          where: 'id = ?',
          whereArgs: [item.id],
        );
      }
      changed = true;
    }
    return changed;
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
        'isDraft': complaint.isDraft ? 1 : 0,
        'syncStatus': complaint.syncStatus.name,
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
          'isDraft': complaint.isDraft ? 1 : 0,
          'syncStatus': ComplaintSyncStatus.pending.name,
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
        {'status': status.name, 'syncStatus': ComplaintSyncStatus.pending.name},
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

  Future<bool> syncNow() async {
    if (_syncing) return false;
    _syncing = true;
    var changed = false;
    try {
      final db = await _database.database;
      final pending = await db.query(
        'complaints',
        where: 'syncStatus = ? AND isDraft = 0',
        whereArgs: [ComplaintSyncStatus.pending.name],
        orderBy: 'createdAt ASC',
      );
      for (final row in pending) {
        final complaint = await _fromRow(row);
        await _remote.upload(_toRemote(complaint));
        await db.update('complaints', {'syncStatus': ComplaintSyncStatus.synced.name}, where: 'id = ?', whereArgs: [complaint.id]);
        changed = true;
      }
      if (await _uploadPendingResponses(db)) changed = true;

      final remoteRows = await _remote.fetchAll();
      for (final row in remoteRows) {
        final localRows = await db.query('complaints', columns: ['syncStatus', 'isDraft', 'isDeleted'], where: 'id = ?', whereArgs: [row['id']], limit: 1);
        if (localRows.isNotEmpty && (localRows.first['isDraft'] == 1 || localRows.first['syncStatus'] == ComplaintSyncStatus.pending.name)) {
          // La réclamation locale est prioritaire, mais les messages de l'autre partie arrivent quand même.
          if (await _saveRemoteResponses(db, row['id'] as String, row['responses'])) changed = true;
          continue;
        }
        if (row['deleted'] == true) {
          await db.delete('complaints', where: 'id = ?', whereArgs: [row['id']]);
          await db.rawDelete(
            'DELETE FROM traductions WHERE reponse_id IN (SELECT id FROM complaint_responses WHERE complaintId = ?)',
            [row['id']],
          );
          await db.delete('complaint_responses', where: 'complaintId = ?', whereArgs: [row['id']]);
          changed = true;
          continue;
        }
        await _saveRemote(db, row);
        await _saveRemoteResponses(db, row['id'] as String, row['responses']);
        changed = true;
      }
      if (changed) _changes.add('*');
      return true;
    } on Object {
      // Keep the local SQLite outbox. A later app resume or retry will sync it.
      return false;
    } finally {
      _syncing = false;
    }
  }

  Map<String, dynamic> _toRemote(ComplaintModel item) => {
    'id': item.id,
    'userId': item.userId,
    'locationId': item.locationId,
    'subject': item.subject,
    'category': item.category.name,
    'description': item.description,
    'status': item.status.name,
    'priority': item.priority.name,
    'createdAt': item.createdAt.toUtc().toIso8601String(),
    'deleted': item.isDeleted,
    'history': item.history.map((entry) => {'status': entry.status.name, 'date': entry.date.toUtc().toIso8601String()}).toList(),
  };

  Future<void> _saveRemote(Database db, Map<String, dynamic> row) async {
    final existingRows = await db.query('complaints', columns: ['photos'], where: 'id = ?', whereArgs: [row['id']], limit: 1);
    final item = {
      'id': row['id'], 'userId': row['userId'], 'locationId': row['locationId'],
      'subject': row['subject'], 'category': row['category'], 'description': row['description'],
      'photos': existingRows.isEmpty ? '[]' : existingRows.first['photos'], 'status': row['status'], 'priority': row['priority'] ?? ComplaintPriority.moyenne.name,
      'createdAt': row['createdAt'], 'isDraft': 0, 'syncStatus': ComplaintSyncStatus.synced.name, 'isDeleted': 0,
    };
    await db.transaction((txn) async {
      final remoteUserId = row['userId'] as String;
      final users = await txn.query('users', columns: ['id'], where: 'id = ?', whereArgs: [remoteUserId], limit: 1);
      if (users.isEmpty) {
        final fakeSalt = base64Encode(utf8.encode('remote-account-no-login'));
        await txn.insert('users', {
          'id': remoteUserId,
          'nom': 'Compte partagé',
          'prenom': 'Utilisateur',
          'email': 'remote_$remoteUserId@studenthub.invalid',
          'telephone': 'remote_$remoteUserId',
          'rolePrincipal': 'locataire',
          'roleSecondaire': null,
          'photo': null,
          'preferences': '{}',
          'passwordHash': fakeSalt,
          'passwordSalt': fakeSalt,
          'createdAt': row['createdAt'],
          'emailVerified': 1,
          'accountStatus': 'approved',
          'isRemote': 1,
        });
      }
      await txn.insert('complaints', item, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('complaint_history', where: 'complaintId = ?', whereArgs: [row['id']]);
      final history = row['history'] is List ? row['history'] as List : const [];
      for (final entry in history) {
        final value = Map<String, dynamic>.from(entry as Map);
        await txn.insert('complaint_history', {'complaintId': row['id'], 'status': value['status'], 'date': value['date']});
      }
    });
  }

  Future<void> delete(String complaintId, {required String userId}) async {
    final db = await _database.database;
    final rows = await db.query(
      'complaints',
      columns: ['photos', 'isDraft'],
      where: 'id = ? AND userId = ?',
      whereArgs: [complaintId, userId],
      limit: 1,
    );
    if (rows.isNotEmpty && rows.first['isDraft'] == 1) {
      await db.delete('complaints', where: 'id = ? AND userId = ?', whereArgs: [complaintId, userId]);
    } else {
      await db.update('complaints', {
        'isDeleted': 1,
        'syncStatus': ComplaintSyncStatus.pending.name,
      }, where: 'id = ? AND userId = ?', whereArgs: [complaintId, userId]);
    }
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
      isDraft: (row['isDraft'] as int? ?? 0) == 1,
      syncStatus: ComplaintSyncStatus.values.firstWhere(
        (value) => value.name == row['syncStatus'],
        orElse: () => ComplaintSyncStatus.pending,
      ),
      isDeleted: (row['isDeleted'] as int? ?? 0) == 1,
    );
  }
}
