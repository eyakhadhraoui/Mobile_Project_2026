import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Backward-compatible access used by the existing account and complaint modules.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Future<Database> get database => DatabaseHelper.instance.database;
}
