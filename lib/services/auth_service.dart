import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/langues.dart';
import '../models/user_model.dart';
import 'api_client.dart';
import 'app_database.dart';

/// Le mot de passe local est correct mais le compte n'existe pas encore sur le
/// serveur partagé (compte créé avant la synchronisation) : il faut prouver
/// l'adresse e-mail par code pour le créer.
class RemoteAccountRequiredException implements Exception {
  const RemoteAccountRequiredException({
    required this.email,
    required this.firstName,
  });
  final String email;
  final String firstName;

  @override
  String toString() =>
      'Confirmez votre adresse e-mail pour activer le partage des annonces.';
}

class AuthService {
  AuthService({AppDatabase? database, ApiClient? api})
    : _database = database ?? AppDatabase.instance,
      _api = api ?? ApiClient(database: database) {
    // Un administrateur a bloqué le compte : la session en cours se ferme.
    ApiClient.compteRefuse.listen((_) async {
      if (await getCurrentUserId() != null) await signOut();
    });
  }

  static const _sessionKey = 'currentUserId';
  static final _passwordHasher = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  );

  final AppDatabase _database;
  final ApiClient _api;
  final StreamController<String?> _authChanges = StreamController.broadcast();

  Stream<String?> get authStateChanges => _authChanges.stream;

  /// Session à restaurer au démarrage. Une session sans jeton serveur (ouverte
  /// hors ligne) reste valable tant que le serveur est injoignable ; dès qu'il
  /// répond, une reconnexion obtient le jeton nécessaire aux annonces.
  Future<String?> restoreSession() async {
    final userId = await getCurrentUserId();
    if (userId == null || ApiClient.baseUri == null) return userId;
    if (await _api.token() != null) return userId;
    if (!await _serveurJoignable()) return userId;
    await signOut();
    return null;
  }

  Future<bool> _serveurJoignable() async {
    try {
      await _api
          .send('GET', '/health', authenticated: false)
          .timeout(const Duration(seconds: 3));
      return true;
    } on ApiException catch (error) {
      return !error.horsConnexion;
    } on TimeoutException {
      return false;
    }
  }

  Future<String?> getCurrentUserId() async {
    final db = await _database.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_sessionKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final userId = rows.first['value'] as String;
    final userRows = await db.query(
      'users',
      columns: ['emailVerified', 'accountStatus'],
      where: 'id = ? AND isRemote = 0',
      whereArgs: [userId],
      limit: 1,
    );
    final canUseSession =
        userRows.isNotEmpty &&
        (userRows.first['emailVerified'] as int? ?? 1) == 1 &&
        (userRows.first['accountStatus'] as String? ?? 'approved') ==
            AccountStatus.approved.name;
    if (!canUseSession) {
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [_sessionKey],
      );
      return null;
    }
    return userId;
  }

  /// Crée le compte localement puis sur le serveur. [verificationToken] est le
  /// jeton délivré par le serveur après la saisie du code e-mail.
  Future<UserModel> register({
    required UserModel user,
    required String password,
    required String verificationToken,
  }) async {
    if (verificationToken.isEmpty) {
      throw StateError('Vérifiez l’adresse e-mail avant de créer le compte.');
    }
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
      (row) =>
          _normalisePhone(row['telephone']! as String) ==
          _normalisePhone(phone),
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
          'emailVerified': 1,
          'accountStatus': AccountStatus.approved.name,
        });
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw Exception(
          'Cette adresse e-mail ou ce numéro de téléphone est déjà utilisé.',
        );
      }
      rethrow;
    }

    try {
      await _registerRemote(
        id: user.id,
        prenom: user.prenom.trim(),
        nom: user.nom.trim(),
        role: user.rolePrincipal,
        password: password,
        verificationToken: verificationToken,
      );
    } catch (_) {
      // Sans compte serveur, les annonces ne pourraient pas être partagées :
      // on annule la création locale pour permettre un nouvel essai.
      await db.delete('users', where: 'id = ?', whereArgs: [user.id]);
      rethrow;
    }
    return user;
  }

  /// Crée (ou relie) le compte serveur d'un compte local existant, après
  /// vérification du mot de passe local et du code e-mail, puis ouvre la session.
  Future<void> linkRemoteAccount({
    required String email,
    required String password,
    required String verificationToken,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'users',
      where: 'email = ? COLLATE NOCASE AND isRemote = 0',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('Compte introuvable sur cet appareil.');
    final row = rows.first;
    final actual = await _hashPassword(
      password,
      base64Decode(row['passwordSalt']! as String),
    );
    if (!_constantTimeEquals(
      actual,
      base64Decode(row['passwordHash']! as String),
    )) {
      throw Exception('Identifiants incorrects.');
    }
    final user = _userFromRow(row);
    final token = await _registerRemote(
      id: user.id,
      prenom: user.prenom,
      nom: user.nom,
      role: user.rolePrincipal,
      password: password,
      verificationToken: verificationToken,
    );
    await _openSession(user.id, token);
  }

  Future<String> _registerRemote({
    required String id,
    required String prenom,
    required String nom,
    required UserRole role,
    required String password,
    required String verificationToken,
  }) async {
    final response = await _api.send(
      'POST',
      '/auth/register',
      authenticated: false,
      body: {
        'verificationToken': verificationToken,
        'id': id,
        'prenom': prenom.isEmpty ? 'Utilisateur' : prenom,
        'nom': nom,
        'role': role == UserRole.administrateur
            ? UserRole.locataire.name
            : role.name,
        'password': password,
      },
    );
    return (response.data as Map)['token'] as String;
  }

  Future<void> _openSession(String userId, String? token) async {
    final db = await _database.database;
    await db.insert('app_settings', {
      'key': _sessionKey,
      'value': userId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _api.saveToken(token);
    _authChanges.add(userId);
  }

  Future<void> signIn({
    required String emailOrPhone,
    required String password,
  }) async {
    final db = await _database.database;
    final credential = emailOrPhone.trim();
    var rows = await db.query(
      'users',
      where: '(email = ? COLLATE NOCASE OR telephone = ?) AND isRemote = 0',
      whereArgs: [credential.toLowerCase(), credential],
      limit: 1,
    );
    if (rows.isEmpty && RegExp(r'\d').hasMatch(credential)) {
      final phoneRows = await db.query(
        'users',
        where: 'telephone IS NOT NULL AND isRemote = 0',
      );
      final normalizedCredential = _normalisePhone(credential);
      rows = phoneRows
          .where(
            (row) =>
                _normalisePhone(row['telephone']! as String) ==
                normalizedCredential,
          )
          .take(1)
          .toList();
    }
    if (rows.isEmpty) {
      // Compte absent de cet appareil (nouveau téléphone, comptes de
      // démonstration) : le serveur peut le reconnaître par son e-mail.
      if (credential.contains('@') && ApiClient.baseUri != null) {
        return _importerCompteServeur(credential.toLowerCase(), password);
      }
      throw Exception('Identifiants incorrects.');
    }

    final row = rows.first;
    final salt = base64Decode(row['passwordSalt']! as String);
    final expected = base64Decode(row['passwordHash']! as String);
    final actual = await _hashPassword(password, salt);
    if (!_constantTimeEquals(actual, expected)) {
      return _connexionAvecMotDePasseServeur(row, password);
    }

    if ((row['emailVerified'] as int? ?? 1) != 1) {
      throw Exception(
        'Veuillez vérifier votre adresse e-mail avant de vous connecter.',
      );
    }
    if ((row['accountStatus'] as String? ?? 'approved') ==
        AccountStatus.blocked.name) {
      throw Exception('Ce compte est bloqué. Contactez l’administrateur.');
    }
    if ((row['accountStatus'] as String? ?? 'approved') !=
        AccountStatus.approved.name) {
      throw Exception('Votre compte attend la validation de l’administrateur.');
    }

    final userId = row['id']! as String;
    String? token;
    try {
      final response = await _api.send(
        'POST',
        '/auth/login',
        authenticated: false,
        body: {'email': row['email'], 'password': password},
      );
      token = (response.data as Map)['token'] as String;
    } on ApiException catch (error) {
      if (error.status == 401) {
        throw RemoteAccountRequiredException(
          email: row['email']! as String,
          firstName: row['prenom']! as String,
        );
      }
      if (error.status == 403) throw Exception(error.message);
      // Serveur absent : connexion hors ligne (réclamations locales seulement).
      token = null;
    }
    await _openSession(userId, token);
  }

  /// Mot de passe différent de la copie locale : il a pu être changé depuis un
  /// autre appareil. Si le serveur l'accepte, la copie locale est mise à jour.
  Future<void> _connexionAvecMotDePasseServeur(
    Map<String, Object?> row,
    String password,
  ) async {
    final String token;
    try {
      final response = await _api.send(
        'POST',
        '/auth/login',
        authenticated: false,
        body: {'email': row['email'], 'password': password},
      );
      token = (response.data as Map)['token'] as String;
    } on ApiException catch (error) {
      if (error.status == 403) throw Exception(error.message);
      throw Exception('Identifiants incorrects.');
    }
    await _enregistrerMotDePasseLocal(row['id']! as String, password);
    await _openSession(row['id']! as String, token);
  }

  Future<void> _enregistrerMotDePasseLocal(
    String userId,
    String password,
  ) async {
    final db = await _database.database;
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    await db.update(
      'users',
      {
        'passwordHash': base64Encode(await _hashPassword(password, salt)),
        'passwordSalt': base64Encode(salt),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Le serveur vérifie le mot de passe ; le compte est alors recréé sur cet
  /// appareil avec le même identifiant (mot de passe haché localement en PBKDF2).
  Future<void> _importerCompteServeur(String email, String password) async {
    final Map<dynamic, dynamic> data;
    try {
      final response = await _api.send(
        'POST',
        '/auth/login',
        authenticated: false,
        body: {'email': email, 'password': password},
      );
      data = response.data as Map;
    } on ApiException catch (error) {
      if (error.isNetwork) {
        throw Exception(
          'Compte inconnu sur cet appareil et serveur injoignable : réessayez avec le serveur démarré.',
        );
      }
      if (error.status == 403) throw Exception(error.message);
      throw Exception('Identifiants incorrects.');
    }
    final user = Map<String, dynamic>.from(data['user'] as Map);
    final id = user['id'] as String;
    final telephone = (user['telephone'] as String? ?? '').trim();
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final ligne = {
      'nom': (user['nom'] as String? ?? '').trim(),
      'prenom': (user['prenom'] as String? ?? 'Utilisateur').trim(),
      'email': email,
      // Colonne obligatoire et unique : valeur provisoire si le serveur ne la connaît pas.
      'telephone': telephone.isEmpty ? 'a-completer-$id' : telephone,
      'rolePrincipal':
          UserRole.values
              .where((r) => r.name == user['role'])
              .firstOrNull
              ?.name ??
          UserRole.locataire.name,
      'passwordHash': base64Encode(await _hashPassword(password, salt)),
      'passwordSalt': base64Encode(salt),
      'emailVerified': 1,
      'accountStatus': AccountStatus.approved.name,
      'isRemote': 0,
    };
    final db = await _database.database;
    try {
      // Un compte « partagé » (isRemote = 1) créé par la synchronisation des
      // réclamations est complété sur place : un REPLACE supprimerait ses
      // réclamations (clé étrangère en cascade).
      final existant = await db.query(
        'users',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existant.isEmpty) {
        await db.insert('users', {
          ...ligne,
          'id': id,
          'roleSecondaire': null,
          'photo': null,
          'preferences': '{}',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await db.update('users', ligne, where: 'id = ?', whereArgs: [id]);
      }
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw Exception(
          'Un autre compte de cet appareil utilise déjà ce numéro de téléphone.',
        );
      }
      rethrow;
    }
    await _openSession(id, data['token'] as String);
  }

  /// true si la session actuelle possède un jeton pour le serveur partagé.
  Future<bool> hasRemoteSession() async => await _api.token() != null;

  Future<void> markEmailVerified(String userId) async {
    final db = await _database.database;
    await db.update(
      'users',
      {'emailVerified': 1, 'accountStatus': AccountStatus.approved.name},
      where: 'id = ? AND accountStatus = ?',
      whereArgs: [userId, AccountStatus.pending.name],
    );
  }

  Future<UserModel?> getUserByEmail(String email) async {
    final db = await _database.database;
    final rows = await db.query(
      'users',
      where: 'email = ? COLLATE NOCASE AND isRemote = 0',
      whereArgs: [email.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : _userFromRow(rows.first);
  }

  /// Comptes du serveur partagé : un blocage vaut alors sur tous les appareils.
  Future<List<UserModel>> getUsersForAdministration() async {
    final data = await _api.get('/admin/users') as List;
    return [
      for (final item in data.whereType<Map>())
        UserModel(
          id: item['id'] as String,
          nom: item['nom'] as String? ?? '',
          prenom: item['prenom'] as String? ?? '',
          email: item['email'] as String? ?? '',
          telephone: item['telephone'] as String? ?? '',
          rolePrincipal: UserRole.values.firstWhere(
            (role) => role.name == item['role'],
            orElse: () => UserRole.locataire,
          ),
          preferences: const {},
          accountStatus: AccountStatus.values.firstWhere(
            (status) => status.name == item['accountStatus'],
            orElse: () => AccountStatus.approved,
          ),
        ),
    ];
  }

  Future<void> setAccountStatus(String userId, AccountStatus status) async {
    await _api.post('/admin/users/$userId/statut', {'statut': status.name});
  }

  static UserModel _userFromRow(Map<String, Object?> row) => UserModel(
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
    preferences:
        jsonDecode(row['preferences']! as String) as Map<String, dynamic>,
    emailVerified: (row['emailVerified'] as int? ?? 1) == 1,
    accountStatus: AccountStatus.values.firstWhere(
      (status) =>
          status.name == (row['accountStatus'] as String? ?? 'approved'),
      orElse: () => AccountStatus.approved,
    ),
    langue: langueValide(row['langue']),
  );

  /// Change le mot de passe du compte connecté après vérification de
  /// [ancien]. Le nouveau est d'abord envoyé au serveur (si la session en a
  /// un), puis enregistré localement. Retourne false si le serveur n'a pas pu
  /// être mis à jour (hors ligne) : il le sera à la prochaine connexion, par la
  /// confirmation e-mail du compte serveur.
  Future<bool> changePassword({
    required String ancien,
    required String nouveau,
  }) async {
    final userId = await getCurrentUserId();
    if (userId == null) throw Exception('Session expirée : reconnectez-vous.');
    final db = await _database.database;
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('Compte introuvable sur cet appareil.');
    final row = rows.first;
    final actual = await _hashPassword(
      ancien,
      base64Decode(row['passwordSalt']! as String),
    );
    if (!_constantTimeEquals(
      actual,
      base64Decode(row['passwordHash']! as String),
    )) {
      throw Exception('Mot de passe actuel incorrect.');
    }
    var serveurAJour = false;
    if (await _api.token() != null) {
      try {
        await _api.put('/me/password', {'ancien': ancien, 'nouveau': nouveau});
        serveurAJour = true;
      } on ApiException {
        // Serveur injoignable ou mot de passe serveur différent : le compte
        // serveur sera resynchronisé à la prochaine connexion.
      }
    }
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    await db.update(
      'users',
      {
        'passwordHash': base64Encode(await _hashPassword(nouveau, salt)),
        'passwordSalt': base64Encode(salt),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    return serveurAJour;
  }

  /// Remplace le mot de passe après saisie du code reçu par e-mail.
  /// [verificationToken] est le jeton délivré par le serveur pour ce code.
  /// Un compte absent du serveur (créé avant le partage) est mis à jour ici seulement.
  Future<void> reinitialiserMotDePasse({
    required String email,
    required String nouveau,
    required String verificationToken,
  }) async {
    var surServeur = true;
    try {
      await _api.send(
        'POST',
        '/auth/password-reset',
        authenticated: false,
        body: {'verificationToken': verificationToken, 'password': nouveau},
      );
    } on ApiException catch (error) {
      if (error.status != 404) rethrow;
      surServeur = false;
    }
    final local = await getUserByEmail(email);
    if (local != null) await _enregistrerMotDePasseLocal(local.id, nouveau);
    if (local == null && !surServeur) {
      throw Exception('Aucun compte trouvé avec cette adresse e-mail.');
    }
  }

  Future<void> signOut() async {
    final db = await _database.database;
    await db.delete('app_settings', where: 'key = ?', whereArgs: [_sessionKey]);
    await _api.saveToken(null);
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
    final demandeRows = await db.query(
      'demandes',
      columns: ['photoPath'],
      where: 'userId = ? AND photoPath IS NOT NULL',
      whereArgs: [userId],
    );
    final photoPaths = <String>[
      if (userRows.isNotEmpty && userRows.first['photo'] is String)
        userRows.first['photo']! as String,
      for (final row in complaintRows)
        ...List<String>.from(jsonDecode(row['photos']! as String) as List),
      for (final row in demandeRows)
        if ((row['photoPath']! as String).contains('maintenance_photos'))
          row['photoPath']! as String,
    ];
    await db.delete('users', where: 'id = ?', whereArgs: [userId]);
    await db.delete('annonces', where: 'cache_utilisateur = ?', whereArgs: [userId]);
    await db.delete('annonces_file', where: 'userId = ?', whereArgs: [userId]);
    await db.delete('messages_file', where: 'userId = ?', whereArgs: [userId]);
    await db.delete('miroir_etat');
    await db.delete('app_settings', where: 'key LIKE ?', whereArgs: ['${ApiClient.prefixeCache(userId)}%']);
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
