import 'dart:convert';

import '../models/user_model.dart';
import 'app_database.dart';

class UserService {
  UserService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<UserModel?> getById(String userId) async {
    final db = await _database.database;
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<UserModel?> getByEmail(String email) async {
    final db = await _database.database;
    final rows = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<void> save(UserModel user) async {
    final db = await _database.database;
    await db.update(
      'users',
      _toRow(user),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<void> delete(String userId) async {
    final db = await _database.database;
    await db.delete('users', where: 'id = ?', whereArgs: [userId]);
  }

  static UserModel _fromRow(Map<String, Object?> row) => UserModel(
    id: row['id']! as String,
    nom: row['nom']! as String,
    prenom: row['prenom']! as String,
    email: row['email']! as String,
    telephone: row['telephone']! as String,
    rolePrincipal: UserRole.values.firstWhere(
      (role) => role.name == row['rolePrincipal'],
      orElse: () => UserRole.locataire,
    ),
    roleSecondaire: UserRole.values
        .where((role) => role.name == row['roleSecondaire'])
        .firstOrNull,
    photo: row['photo'] as String?,
    preferences: Map<String, dynamic>.from(
      jsonDecode(row['preferences']! as String) as Map,
    ),
    emailVerified: (row['emailVerified'] as int? ?? 1) == 1,
    accountStatus: AccountStatus.values.firstWhere(
      (status) => status.name == (row['accountStatus'] as String? ?? 'approved'),
      orElse: () => AccountStatus.approved,
    ),
  );

  static Map<String, Object?> _toRow(UserModel user) => {
    'nom': user.nom,
    'prenom': user.prenom,
    'email': user.email.trim().toLowerCase(),
    'telephone': user.telephone.trim(),
    'rolePrincipal': user.rolePrincipal.name,
    'roleSecondaire': user.roleSecondaire?.name,
    'photo': user.photo,
    'preferences': jsonEncode(user.preferences),
    'emailVerified': user.emailVerified ? 1 : 0,
    'accountStatus': user.accountStatus.name,
  };
}
