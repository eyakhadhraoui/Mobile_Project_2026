import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/constants/app_constants.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async {
    final current = _database;
    if (current != null) return current;

    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, AppConstants.databaseFileName),
      version: 3,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id TEXT PRIMARY KEY,
            nom TEXT NOT NULL,
            prenom TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE COLLATE NOCASE,
            telephone TEXT NOT NULL UNIQUE,
            rolePrincipal TEXT NOT NULL,
            roleSecondaire TEXT,
            photo TEXT,
            preferences TEXT NOT NULL DEFAULT '{}',
            passwordHash TEXT NOT NULL,
            passwordSalt TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            emailVerified INTEGER NOT NULL DEFAULT 0,
            accountStatus TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
        await db.execute('''
          CREATE TABLE app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE complaints (
            id TEXT PRIMARY KEY,
            userId TEXT NOT NULL,
            locationId TEXT NOT NULL,
            subject TEXT NOT NULL,
            category TEXT NOT NULL,
            description TEXT NOT NULL,
            photos TEXT NOT NULL DEFAULT '[]',
            status TEXT NOT NULL,
            priority TEXT NOT NULL DEFAULT 'moyenne',
            createdAt TEXT NOT NULL,
            FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE complaint_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            complaintId TEXT NOT NULL,
            status TEXT NOT NULL,
            date TEXT NOT NULL,
            FOREIGN KEY (complaintId) REFERENCES complaints(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX complaints_user_date ON complaints(userId, createdAt DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE complaints ADD COLUMN priority TEXT NOT NULL DEFAULT 'moyenne'",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE users ADD COLUMN emailVerified INTEGER NOT NULL DEFAULT 1',
          );
          await db.execute(
            "ALTER TABLE users ADD COLUMN accountStatus TEXT NOT NULL DEFAULT 'approved'",
          );
        }
      },
    );
    _database = db;
    return db;
  }
}
