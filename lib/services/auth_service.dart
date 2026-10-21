import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../models/user_model.dart';
import 'app_database.dart';

class AuthService {
  AuthService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  static const _sessionKey = 'currentUserId';
  static final _passwordHasher = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  );

  final AppDatabase _database;
  final StreamController<String?> _authChanges = StreamController.broadcast();

  Stream<String?> get authStateChanges => _authChanges.stream;

  Future<String?> getCurrentUserId() async {
    final db = await _database.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_sessionKey],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<UserModel> register({
    required UserModel user,
    required String password,
  }) async {
    final db = await _database.database;
    final email = user.email.trim().toLowerCase();
    final phone = user.telephone.trim();
    final existingEmails = await db.query(
      'users',
      columns: ['id'],
      where: 'email = ? COLLATE NOCASE',
      whereArgs: [email],
      limit: 1,
    );
    if (existingEmails.isNotEmpty) {
      throw Exception('Cette adresse e-mail est déjà utilisée.');
    }
    final existingUsers = await db.query('users', columns: ['telephone']);
    if (existingUsers.any(
      (row) => _normalisePhone(row['telephone']! as String) == _normalisePhone(phone),
    )) {
      throw Exception('Ce numéro de téléphone est déjà utilisé.');
    }
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final passwordHash = base64Encode(await _hashPassword(password, salt));

    try {
      await db.transaction((txn) async {
        await txn.insert('users', {
          'id': user.id,
          'nom': user.nom.trim(),
          'prenom': user.prenom.trim(),
          'email': email,
          'telephone': phone,
          'rolePrincipal': user.rolePrincipal.name,
          'roleSecondaire': user.roleSecondaire?.name,
          'photo': user.photo,
          'preferences': jsonEncode(user.preferences),
          'passwordHash': passwordHash,
          'passwordSalt': base64Encode(salt),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'emailVerified': 0,
          'accountStatus': AccountStatus.pending.name,
        });
        await txn.insert('app_settings', {
          'key': _sessionKey,
          'value': user.id,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw Exception(
          'Cette adresse e-mail ou ce numéro de téléphone est déjà utilisé.',
        );
      }
      rethrow;
    }

    _authChanges.add(user.id);
    return user;
  }

  Future<void> signIn({
    required String emailOrPhone,
    required String password,
  }) async {
    final db = await _database.database;
    final credential = emailOrPhone.trim();
    var rows = await db.query(
      'users',
      where: 'email = ? COLLATE NOCASE OR telephone = ?',
      whereArgs: [credential.toLowerCase(), credential],
      limit: 1,
    );
    if (rows.isEmpty && RegExp(r'\d').hasMatch(credential)) {
      final phoneRows = await db.query(
        'users',
        where: 'telephone IS NOT NULL',
      );
      final normalizedCredential = _normalisePhone(credential);
      rows = phoneRows
          .where(
            (row) => _normalisePhone(row['telephone']! as String) == normalizedCredential,
          )
          .take(1)
          .toList();
    }
    if (rows.isEmpty) throw Exception('Identifiants incorrects.');

    final row = rows.first;
    final salt = base64Decode(row['passwordSalt']! as String);
    final expected = base64Decode(row['passwordHash']! as String);
    final actual = await _hashPassword(password, salt);
    if (!_constantTimeEquals(actual, expected)) {
      throw Exception('Identifiants incorrects.');
    }

    if ((row['emailVerified'] as int? ?? 1) != 1) {
      throw Exception('Veuillez vérifier votre adresse e-mail avant de vous connecter.');
    }
    if ((row['accountStatus'] as String? ?? 'approved') == AccountStatus.blocked.name) {
      throw Exception('Ce compte est bloqué. Contactez l’administrateur.');
    }
    if ((row['accountStatus'] as String? ?? 'approved') != AccountStatus.approved.name) {
      throw Exception('Votre compte attend la validation de l’administrateur.');
    }

    final userId = row['id']! as String;
    await db.insert('app_settings', {
      'key': _sessionKey,
      'value': userId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _authChanges.add(userId);
  }

  Future<void> markEmailVerified(String userId) async {
    final db = await _database.database;
    await db.update('users', {'emailVerified': 1}, where: 'id = ?', whereArgs: [userId]);
  }

  Future<UserModel?> getUserByEmail(String email) async {
    final db = await _database.database;
    final rows = await db.query('users', where: 'email = ? COLLATE NOCASE', whereArgs: [email.trim()], limit: 1);
    return rows.isEmpty ? null : _userFromRow(rows.first);
  }

  Future<List<UserModel>> getUsersForAdministration() async {
    final db = await _database.database;
    final rows = await db.query('users', orderBy: 'createdAt DESC');
    return rows.map(_userFromRow).toList();
  }

  Future<void> setAccountStatus(String userId, AccountStatus status) async {
    final db = await _database.database;
    await db.update('users', {'accountStatus': status.name}, where: 'id = ?', whereArgs: [userId]);
    if (status == AccountStatus.blocked && await getCurrentUserId() == userId) {
      await signOut();
    }
  }

  static UserModel _userFromRow(Map<String, Object?> row) => UserModel(
    id: row['id']! as String,
    nom: row['nom']! as String,
    prenom: row['prenom']! as String,
    email: row['email']! as String,
    telephone: row['telephone']! as String,
    rolePrincipal: UserRole.values.firstWhere((role) => role.name == row['rolePrincipal'], orElse: () => UserRole.locataire),
    roleSecondaire: UserRole.values.where((role) => role.name == row['roleSecondaire']).firstOrNull,
    photo: row['photo'] as String?,
    preferences: jsonDecode(row['preferences']! as String) as Map<String, dynamic>,
    emailVerified: (row['emailVerified'] as int? ?? 1) == 1,
    accountStatus: AccountStatus.values.firstWhere((status) => status.name == (row['accountStatus'] as String? ?? 'approved'), orElse: () => AccountStatus.approved),
  );

  Future<void> sendPasswordResetEmail(String email) async {
    throw UnsupportedError(
      'La réinitialisation par e-mail nécessite un service en ligne. '
      'Cette version SQLite conserve les comptes uniquement sur cet appareil.',
    );
  }

  Future<void> signOut() async {
    final db = await _database.database;
    await db.delete('app_settings', where: 'key = ?', whereArgs: [_sessionKey]);
    _authChanges.add(null);
  }

  Future<void> deleteAccount() async {
    final userId = await getCurrentUserId();
    if (userId == null) return;
    final db = await _database.database;
    final userRows = await db.query(
      'users',
      columns: ['photo'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    final complaintRows = await db.query(
      'complaints',
      columns: ['photos'],
      where: 'userId = ?',
      whereArgs: [userId],
    );
    final photoPaths = <String>[
      if (userRows.isNotEmpty && userRows.first['photo'] is String)
        userRows.first['photo']! as String,
      for (final row in complaintRows)
        ...List<String>.from(jsonDecode(row['photos']! as String) as List),
    ];
    await db.delete('users', where: 'id = ?', whereArgs: [userId]);
    await signOut();
    for (final path in photoPaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Account and database deletion should succeed even if a cached image
        // was already removed by the operating system.
      }
    }
  }

  Future<List<int>> _hashPassword(String password, List<int> salt) async {
    final key = await _passwordHasher.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  bool _constantTimeEquals(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var i = 0; i < first.length; i++) {
      difference |= first[i] ^ second[i];
    }
    return difference == 0;
  }

  String _normalisePhone(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.length == 11 && digits.startsWith('216')) {
      digits = digits.substring(3);
    }
    return digits;
  }
}
