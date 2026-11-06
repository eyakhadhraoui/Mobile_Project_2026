import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studenthub/models/annonce.dart';
import 'package:studenthub/providers/annonce_provider.dart';
import 'package:studenthub/services/annonce_cache_service.dart';
import 'package:studenthub/services/annonce_service.dart';
import 'package:studenthub/services/api_client.dart';
import 'package:studenthub/services/database_helper.dart';
import 'package:studenthub/services/heure_service.dart';
import 'package:studenthub/services/notification_service.dart';
import 'package:studenthub/services/planificateur_service.dart';

/// Réponse de TimeAPI : 1er janvier 2030, 12:00 à Tunis (UTC+1), soit 11:00 UTC.
/// Volontairement très différente de l'horloge de la machine de test : on
/// vérifie ainsi que c'est bien l'heure de l'API qui est utilisée.
const _reponseTimeApi = {
  'year': 2030,
  'month': 1,
  'day': 1,
  'hour': 12,
  'minute': 0,
  'seconds': 0,
  'milliSeconds': 0,
  'dateTime': '2030-01-01T12:00:00',
  'timeZone': 'Africa/Tunis',
};
final _heureApi = DateTime.utc(2030, 1, 1, 11);

HeureService _heureOfficielle() => HeureService(
  client: MockClient((request) async {
    expect(request.url.toString(), 'https://timeapi.io/api/Time/current/zone?timeZone=Africa%2FTunis');
    return http.Response(json.encode(_reponseTimeApi), 200);
  }),
);

Annonce _annonce(String id, {StatutAnnonce statut = StatutAnnonce.programmee, DateTime? date, String proprietaire = 'me'}) =>
    Annonce(
      id: id,
      categorie: 'Avis',
      titre: 'Annonce $id',
      description: 'Description',
      statut: statut,
      datePublication: date,
      proprietaireId: proprietaire,
      createdAt: DateTime.utc(2026, 11, 5),
    );

/// Faux service de notifications : enregistre les appels.
class _Notifications implements NotificationsPublication {
  final programmees = <String, DateTime>{};
  final annulees = <String>[];
  @override
  Future<void> initialiser() async {}
  @override
  Future<bool> demanderPermissions() async => true;
  @override
  Future<void> programmer({required String annonceId, required String titre, required DateTime date, bool enValidation = false}) async =>
      programmees[annonceId] = date;
  @override
  Future<void> annuler(String annonceId) async {
    programmees.remove(annonceId);
    annulees.add(annonceId);
  }

  @override
  Future<void> annulerTout() async => programmees.clear();
}

/// Faux serveur : une annonce « en attente » appartenant à l'utilisateur.
class _Serveur extends AnnonceService {
  _Serveur(this.items);
  List<Annonce> items;

  @override
  Future<int> migrerAnnoncesLocales(String userId) async => 0;

  @override
  Future<AnnoncesPage?> lister({String? etag}) async =>
      AnnoncesPage(annonces: items, meId: 'me', meRole: 'proprietaire', etag: 'v1');

  @override
  Future<Annonce> programmer(String id, DateTime date) async =>
      _maj(id, (a) => a.copyWith(statut: StatutAnnonce.programmee, datePublication: date.toUtc()));

  @override
  Future<Annonce> annulerProgrammation(String id, {bool publierMaintenant = true}) async => _maj(
    id,
    (a) => a.copyWith(statut: publierMaintenant ? StatutAnnonce.publiee : StatutAnnonce.enAttente, datePublication: null),
  );

  Annonce _maj(String id, Annonce Function(Annonce) change) {
    final annonce = change(items.firstWhere((a) => a.id == id));
    items = [for (final a in items) a.id == id ? annonce : a];
    return annonce;
  }
}

/// Attend qu'une condition devienne vraie (opérations SQLite asynchrones).
Future<void> _attendre(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  late Directory dossier;
  late DatabaseHelper base;
  late AnnonceCacheService cache;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('studenthub_test_');
    base = DatabaseHelper.forTests(path: p.join(dossier.path, 'studenthub.db'));
    cache = AnnonceCacheService(databaseHelper: base);
  });

  tearDown(() async {
    await base.fermer();
    await dossier.delete(recursive: true);
  });

  group('Migration SQLite', () {
    test('version 9 → 10 : ajoute date_publication sans perdre les annonces', () async {
      final chemin = p.join(dossier.path, 'ancienne.db');
      // Base telle qu'elle existait en version 9 (table annonces sans les nouvelles colonnes).
      final ancienne = await openDatabase(
        chemin,
        version: 9,
        onCreate: (db, _) async {
          // Une base v9 réelle contient aussi la table users (complétée en v11).
          await db.execute('CREATE TABLE users (id TEXT PRIMARY KEY, nom TEXT NOT NULL)');
          await db.execute('''
            CREATE TABLE annonces (
              id TEXT PRIMARY KEY, titre TEXT NOT NULL, description TEXT NOT NULL,
              typeLocation TEXT NOT NULL, loyer REAL NOT NULL, surface REAL NOT NULL,
              chambres INTEGER NOT NULL, etage INTEGER, ville TEXT NOT NULL,
              quartier TEXT NOT NULL, adresse TEXT NOT NULL, photos TEXT NOT NULL DEFAULT '[]',
              statut TEXT NOT NULL DEFAULT 'enAttente', proprietaireId TEXT NOT NULL,
              commentaires TEXT NOT NULL DEFAULT '[]', autoriserCommentaires INTEGER NOT NULL DEFAULT 1
            )''');
          await db.insert('annonces', {
            'id': 'ancienne',
            'titre': 'Studio',
            'description': 'Ancienne annonce',
            'typeLocation': 'Avis',
            'loyer': 0,
            'surface': 0,
            'chambres': 0,
            'ville': '',
            'quartier': '',
            'adresse': '',
            'proprietaireId': 'me',
          });
        },
      );
      await ancienne.close();

      final helper = DatabaseHelper.forTests(path: chemin);
      final db = await helper.database;
      expect(await db.getVersion(), DatabaseHelper.versionSchema);
      final colonnes = (await db.rawQuery('PRAGMA table_info(annonces)')).map((c) => c['name']).toSet();
      expect(colonnes, containsAll(['date_publication', 'categorie', 'cache_utilisateur', 'donnees']));
      final lignes = await db.query('annonces');
      expect(lignes, hasLength(1));
      expect(lignes.single['titre'], 'Studio');
      expect(lignes.single['statut'], 'enAttente');
      expect(lignes.single['date_publication'], isNull);
      // Toujours reconnue comme annonce locale à migrer (et non comme cache).
      expect(lignes.single['cache_utilisateur'], isNull);
      await helper.fermer();
    });

    test('nouvelle installation : le schéma contient date_publication', () async {
      final db = await base.database;
      final colonnes = (await db.rawQuery('PRAGMA table_info(annonces)')).map((c) => c['name']).toSet();
      expect(colonnes, contains('date_publication'));
    });
  });

  group('Modèle', () {
    test('statut programmee et datePublication ISO UTC (toJson / fromJson / copyWith)', () {
      final date = DateTime.utc(2030, 1, 1, 10, 30, 15, 999);
      final annonce = _annonce('a', date: date);
      final json = annonce.toJson();
      expect(json['statut'], 'programmee');
      expect(json['datePublication'], '2030-01-01T10:30:15.000Z');
      final relue = Annonce.fromJson(json);
      expect(relue.statut, StatutAnnonce.programmee);
      expect(relue.datePublication, DateTime.utc(2030, 1, 1, 10, 30, 15));
      expect(relue.copyWith(datePublication: null).datePublication, isNull);
      expect(relue.copyWith(titre: 'x').datePublication, relue.datePublication);
      expect(annonce.toPayload()['datePublication'], '2030-01-01T10:30:15.000Z');
      expect(annonce.libelleProgrammation, startsWith('Programmée le '));
    });
  });

  group('Planificateur', () {
    test('publie les annonces échues selon l’heure de l’API ; les autres restent programmées', () async {
      await cache.remplacer('me', [
        _annonce('echue', date: _heureApi.subtract(const Duration(hours: 1))),
        _annonce('future', date: _heureApi.add(const Duration(hours: 1))),
        _annonce('publiee', statut: StatutAnnonce.publiee),
      ]);
      final planificateur = PlanificateurService(cache: cache, heure: _heureOfficielle());

      final publiees = await planificateur.publierAnnoncesEchues(userId: 'me');

      expect(publiees.map((a) => a.id), ['echue']);
      final enBase = {for (final a in await cache.lire('me')) a.id: a.statut};
      expect(enBase['echue'], StatutAnnonce.publiee);
      expect(enBase['future'], StatutAnnonce.programmee);
      expect(enBase['publiee'], StatutAnnonce.publiee);
      // Second passage : plus rien à publier.
      expect(await planificateur.publierAnnoncesEchues(userId: 'me'), isEmpty);
    });

    test('rattrapage : API injoignable → horloge locale, l’annonce passée est publiée', () async {
      await cache.remplacer('me', [
        _annonce('manquee', date: DateTime.now().subtract(const Duration(days: 2))),
        _annonce('demain', date: DateTime.now().add(const Duration(days: 1))),
      ]);
      final heure = HeureService(client: MockClient((_) async => throw const SocketException('hors ligne')));
      final publiees = await PlanificateurService(cache: cache, heure: heure).publierAnnoncesEchues(userId: 'me');
      expect(publiees.map((a) => a.id), ['manquee']);
    });

    test('avec modération, l’annonce échue passe en attente de validation', () async {
      await cache.remplacer('me', [_annonce('echue', date: _heureApi.subtract(const Duration(minutes: 1)))]);
      final publiees = await PlanificateurService(cache: cache, heure: _heureOfficielle())
          .publierAnnoncesEchues(userId: 'me', statutCible: (_) => StatutAnnonce.enAttente);
      expect(publiees.single.statut, StatutAnnonce.enAttente);
      expect((await cache.lire('me')).single.statut, StatutAnnonce.enAttente);
    });
  });

  group('HeureService', () {
    test('heure officielle convertie de Tunis en UTC', () async {
      final resultat = await _heureOfficielle().obtenirHeure();
      expect(resultat.source, SourceHeure.officielle);
      expect(resultat.heure, _heureApi);
      expect(resultat.erreur, isNull);
    });

    test('repli sur l’horloge locale : réseau absent, statut ≠ 200, JSON invalide', () async {
      final horloge = DateTime.utc(2026, 11, 5, 9);
      final cas = <String, MockClient>{
        'connexion': MockClient((_) async => throw const SocketException('hors ligne')),
        'code 503': MockClient((_) async => http.Response('indisponible', 503)),
        'illisible': MockClient((_) async => http.Response('<html>', 200)),
        'connexion au service': MockClient((_) async => throw http.ClientException('refusée')),
        'délai': MockClient((_) async => throw TimeoutException('trop long')),
      };
      for (final entree in cas.entries) {
        final resultat = await HeureService(client: entree.value, horloge: () => horloge).obtenirHeure();
        expect(resultat.source, SourceHeure.locale, reason: entree.key);
        expect(resultat.heure, horloge, reason: entree.key);
        expect(resultat.erreur, contains(entree.key), reason: entree.key);
      }
    });

    test('l’écart avec l’heure officielle est mémorisé (une seule requête)', () async {
      var appels = 0;
      final service = HeureService(
        client: MockClient((_) async {
          appels++;
          return http.Response(json.encode(_reponseTimeApi), 200);
        }),
      );
      await service.heureActuelle();
      final seconde = await service.heureActuelle();
      expect(appels, 1);
      expect(seconde.difference(_heureApi).inSeconds.abs(), lessThan(5));
    });
  });

  group('AnnonceProvider', () {
    test('programmer puis annuler : statut, cache SQLite et notification', () async {
      final serveur = _Serveur([_annonce('a1', statut: StatutAnnonce.enAttente)]);
      final notifications = _Notifications();
      final provider = AnnonceProvider(
        service: serveur,
        cache: cache,
        planificateur: PlanificateurService(cache: cache, heure: _heureOfficielle()),
        notifications: notifications,
      );
      addTearDown(provider.dispose);
      provider.utilisateur('me');
      await _attendre(() => provider.annonces.isNotEmpty);

      final date = DateTime.now().add(const Duration(days: 1));
      final programmee = await provider.programmer(provider.parId('a1')!, date);
      expect(programmee.statut, StatutAnnonce.programmee);
      expect(provider.parId('a1')!.estProgrammee, isTrue);
      expect(provider.operationEnCours, isFalse);
      expect(notifications.programmees['a1'], date.toUtc());
      await _attendre(() => true);
      final ligne = (await (await base.database).query('annonces', where: 'id = ?', whereArgs: ['a1'])).single;
      expect(ligne['statut'], 'programmee');
      expect(ligne['date_publication'], isoUtc(date));

      await provider.annulerProgrammation('a1', publierMaintenant: false);
      expect(provider.parId('a1')!.statut, StatutAnnonce.enAttente);
      expect(notifications.annulees, contains('a1'));
      expect(notifications.programmees, isNot(contains('a1')));
    });

    test('rafraichir publie l’annonce échue et notifie les écouteurs', () async {
      final serveur = _Serveur([_annonce('a1', date: _heureApi.add(const Duration(minutes: 5)))]);
      final provider = AnnonceProvider(
        service: serveur,
        cache: cache,
        planificateur: PlanificateurService(cache: cache, heure: _heureOfficielle()),
        notifications: _Notifications(),
      );
      addTearDown(provider.dispose);
      provider.utilisateur('me');
      await _attendre(() => provider.annonces.isNotEmpty);
      expect(await provider.rafraichir(), 0); // 12:05 > 12:00 : pas encore échue

      // L'heure passe : le planificateur doit publier l'annonce.
      await cache.enregistrer('me', _annonce('a1', date: _heureApi.subtract(const Duration(minutes: 1))));
      var notifie = false;
      provider.addListener(() => notifie = true);
      serveur.items = [_annonce('a1', statut: StatutAnnonce.publiee)];
      expect(await provider.rafraichir(), 1);
      expect(notifie, isTrue);
      expect(provider.parId('a1')!.estPubliee, isTrue);
      // Laisse finir la resynchronisation lancée en arrière-plan avant de fermer la base.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    test('hors ligne : la liste vient du cache SQLite', () async {
      await cache.remplacer('me', [_annonce('cachee', statut: StatutAnnonce.publiee)]);
      final provider = AnnonceProvider(
        service: _ServeurInjoignable(),
        cache: cache,
        planificateur: PlanificateurService(cache: cache, heure: _heureOfficielle()),
      );
      addTearDown(provider.dispose);
      provider.utilisateur('me');
      await _attendre(() => provider.annonces.isNotEmpty);
      expect(provider.horsLigne, isTrue);
      expect(provider.annonces.single.id, 'cachee');
    });
  });
}

class _ServeurInjoignable extends AnnonceService {
  @override
  Future<int> migrerAnnoncesLocales(String userId) async => 0;
  @override
  Future<AnnoncesPage?> lister({String? etag}) async => throw const ApiException('Serveur injoignable');
}
