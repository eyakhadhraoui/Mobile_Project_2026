import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studenthub/models/user_model.dart';
import 'package:studenthub/services/api_client.dart';
import 'package:studenthub/services/app_database.dart';
import 'package:studenthub/services/auth_service.dart';
import 'package:studenthub/services/database_helper.dart';

class _Db implements AppDatabase {
  _Db(this.helper);
  final DatabaseHelper helper;
  @override
  Future<Database> get database => helper.database;
}

/// Serveur simulé : mot de passe courant et réponses forcées par route.
class _Api extends ApiClient {
  _Api(AppDatabase db) : super(database: db);

  String motDePasseServeur = 'AncienMdp1!';
  final erreurs = <String, ApiException>{};
  final appels = <(String, String, Object?)>[];
  Object? listeAdmin;

  @override
  Future<ApiResponse> send(
    String method,
    String path, {
    Object? body,
    String? etag,
    bool authenticated = true,
    List<int>? bytes,
  }) async {
    appels.add((method, path, body));
    if (erreurs[path] case final erreur?) throw erreur;
    final data = body is Map ? body : const {};
    switch (path) {
      case '/auth/register':
        return const ApiResponse(201, {'token': 'jeton'}, null);
      case '/auth/login':
        if (data['password'] != motDePasseServeur) {
          throw const ApiException('Refusé', status: 401);
        }
        return const ApiResponse(200, {'token': 'jeton'}, null);
      case '/auth/password-reset':
        motDePasseServeur = data['password'] as String;
        return const ApiResponse(200, {'updated': true}, null);
      case '/admin/users':
        return ApiResponse(200, listeAdmin, null);
      default:
        return const ApiResponse(200, {}, null);
    }
  }
}

const _email = 'omar@test.local';
const _ancien = 'AncienMdp1!';
const _nouveau = 'NouveauMdp2!';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dossier;
  late DatabaseHelper base;
  late _Api api;
  late AuthService service;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('auth_reset');
    base = DatabaseHelper.forTests(path: p.join(dossier.path, 'studenthub.db'));
    final db = _Db(base);
    api = _Api(db);
    service = AuthService(database: db, api: api);
    await service.register(
      user: const UserModel(
        id: 'u1',
        nom: 'Mansouri',
        prenom: 'Omar',
        email: _email,
        telephone: '50777888',
        rolePrincipal: UserRole.locataire,
        preferences: {},
      ),
      password: _ancien,
      verificationToken: 'code',
    );
  });

  tearDown(() async {
    await (await base.database).close();
    await dossier.delete(recursive: true);
  });

  Future<void> connecter(String motDePasse) =>
      service.signIn(emailOrPhone: _email, password: motDePasse);

  group('mot de passe oublié', () {
    test('le nouveau mot de passe remplace l’ancien partout', () async {
      await service.reinitialiserMotDePasse(
        email: _email,
        nouveau: _nouveau,
        verificationToken: 'jeton-email',
      );
      expect(api.motDePasseServeur, _nouveau);
      await expectLater(connecter(_ancien), throwsA(isA<Exception>()));
      expect(await service.getCurrentUserId(), isNull);
      await connecter(_nouveau);
      expect(await service.getCurrentUserId(), 'u1');
    });

    test('serveur injoignable : rien ne change sur l’appareil', () async {
      api.erreurs['/auth/password-reset'] = const ApiException('Hors ligne');
      await expectLater(
        service.reinitialiserMotDePasse(
          email: _email,
          nouveau: _nouveau,
          verificationToken: 'jeton-email',
        ),
        throwsA(isA<ApiException>()),
      );
      await connecter(_ancien);
      expect(await service.getCurrentUserId(), 'u1');
    });

    test('compte absent du serveur : mis à jour sur l’appareil', () async {
      api.erreurs['/auth/password-reset'] = const ApiException('Inconnu', status: 404);
      await service.reinitialiserMotDePasse(
        email: _email,
        nouveau: _nouveau,
        verificationToken: 'jeton-email',
      );
      api.motDePasseServeur = _nouveau;
      await connecter(_nouveau);
      expect(await service.getCurrentUserId(), 'u1');
    });

    test('adresse inconnue partout : erreur', () async {
      api.erreurs['/auth/password-reset'] = const ApiException('Inconnu', status: 404);
      await expectLater(
        service.reinitialiserMotDePasse(
          email: 'personne@test.local',
          nouveau: _nouveau,
          verificationToken: 'jeton-email',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('mot de passe changé sur un autre appareil : copie locale mise à jour', () async {
      api.motDePasseServeur = _nouveau;
      await connecter(_nouveau);
      expect(await service.getCurrentUserId(), 'u1');
      await service.signOut();
      api.erreurs['/auth/login'] = const ApiException('Hors ligne');
      await connecter(_nouveau);
      expect(await service.getCurrentUserId(), 'u1');
    });
  });

  group('comptes bloqués', () {
    test('la connexion est refusée avec le message du serveur', () async {
      api.erreurs['/auth/login'] = const ApiException(
        'Ce compte est bloqué.',
        status: 403,
        code: 'account_blocked',
      );
      await expectLater(
        connecter(_ancien),
        throwsA(predicate((e) => e.toString().contains('Ce compte est bloqué.'))),
      );
      expect(await service.getCurrentUserId(), isNull);
    });
  });

  group('administration', () {
    test('la liste vient du serveur', () async {
      api.listeAdmin = [
        {
          'id': 'u2',
          'prenom': 'Sami',
          'nom': 'Ben',
          'email': 'sami@test.local',
          'role': 'proprietaire',
          'accountStatus': 'blocked',
        },
      ];
      final comptes = await service.getUsersForAdministration();
      expect(comptes.single.rolePrincipal, UserRole.proprietaire);
      expect(comptes.single.accountStatus, AccountStatus.blocked);
    });

    test('le changement de statut est envoyé au serveur', () async {
      await service.setAccountStatus('u2', AccountStatus.blocked);
      final appel = api.appels.last;
      expect(appel.$2, '/admin/users/u2/statut');
      expect(appel.$3, {'statut': 'blocked'});
    });
  });
}
