import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studenthub/models/annonce.dart';
import 'package:studenthub/models/trajet.dart';
import 'package:studenthub/providers/trajet_provider.dart';
import 'package:studenthub/services/database_helper.dart';
import 'package:studenthub/services/geocodage_service.dart';
import 'package:studenthub/services/trajet_service.dart';

const _fac = Coordonnees(lat: 36.8440, lon: 10.1539);
const _facUniversite = Universite(nom: 'Faculté des Sciences de Tunis', lat: 36.8440, lon: 10.1539);

/// Réponse OSRM « table » : une ligne par logement, une colonne (l'université).
http.Response _table(List<num?> durees, List<num?> distances) => http.Response(
  jsonEncode({
    'code': 'Ok',
    'durations': [for (final d in durees) [d]],
    'distances': [for (final d in distances) [d]],
  }),
  200,
);

Annonce _logement(String id, {String adresse = '', String quartier = '', String ville = 'Tunis'}) => Annonce(
  id: id,
  categorie: 'Logement',
  titre: 'Logement $id',
  description: 'd',
  typeLocation: 'Studio',
  loyer: 400,
  surface: 20,
  chambres: 1,
  ville: ville,
  quartier: quartier,
  adresse: adresse,
  statut: StatutAnnonce.publiee,
  proprietaireId: 'proprio',
);

void main() {
  late Directory dossier;
  late DatabaseHelper base;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('studenthub_trajet_');
    base = DatabaseHelper.forTests(path: p.join(dossier.path, 'studenthub.db'));
  });

  tearDown(() async {
    await base.fermer();
    await dossier.delete(recursive: true);
  });

  group('TrajetService (OSRM table)', () {
    test('URL OSRM : serveur piéton, longitude,latitude, sources et destination', () async {
      late http.Request requete;
      final service = TrajetService(
        databaseHelper: base,
        client: MockClient((request) async {
          requete = request;
          return _table([720, 1500], [900, 1800]);
        }),
      );
      final resultats = await service.calculer(
        universite: _fac,
        logements: const {'a': Coordonnees(lat: 36.83, lon: 10.17), 'b': Coordonnees(lat: 36.80, lon: 10.18)},
        mode: ModeTrajet.pied,
      );
      final url = requete.url.toString();
      expect(url, startsWith('https://routing.openstreetmap.de/routed-foot/table/v1/driving/'));
      expect(url, contains('10.153900,36.844000;10.170000,36.830000;10.180000,36.800000'));
      expect(requete.url.queryParameters['sources'], '1;2');
      expect(requete.url.queryParameters['destinations'], '0');
      expect(requete.headers['User-Agent'], isNot(contains('@')));
      expect(resultats['a']!.duree, const Duration(minutes: 12));
      expect(resultats['b']!.distanceMetres, 1800);
    });

    test('voiture : serveur router.project-osrm.org', () async {
      late Uri appelee;
      final service = TrajetService(
        databaseHelper: base,
        client: MockClient((request) async {
          appelee = request.url;
          return _table([300], [2500]);
        }),
      );
      await service.calculer(universite: _fac, logements: const {'a': Coordonnees(lat: 36.83, lon: 10.17)}, mode: ModeTrajet.voiture);
      expect(appelee.host, 'router.project-osrm.org');
    });

    test('pas d’itinéraire (null) conservé, cache utilisé au second appel', () async {
      var appels = 0;
      final service = TrajetService(
        databaseHelper: base,
        client: MockClient((_) async {
          appels++;
          return _table([600, null], [700, null]);
        }),
      );
      const logements = {'a': Coordonnees(lat: 36.83, lon: 10.17), 'ile': Coordonnees(lat: 37.5, lon: 11.0)};
      for (var i = 0; i < 2; i++) {
        final resultats = await service.calculer(universite: _fac, logements: logements, mode: ModeTrajet.pied);
        expect(resultats['a']!.duree, const Duration(minutes: 10));
        expect(resultats.containsKey('ile'), isTrue);
        expect(resultats['ile'], isNull);
      }
      expect(appels, 1);
    });

    test('plus de 25 logements : plusieurs requêtes, résultats dans l’ordre', () async {
      final tailles = <int>[];
      final service = TrajetService(
        databaseHelper: base,
        client: MockClient((request) async {
          final sources = request.url.queryParameters['sources']!.split(';');
          tailles.add(sources.length);
          return _table([for (final s in sources) int.parse(s) * 60], [for (final s in sources) int.parse(s) * 100]);
        }),
      );
      final logements = {for (var i = 0; i < 30; i++) 'l$i': Coordonnees(lat: 36.8 + i / 1000, lon: 10.1)};
      final resultats = await service.calculer(universite: _fac, logements: logements, mode: ModeTrajet.pied);
      expect(tailles, [25, 5]);
      expect(resultats['l0']!.duree, const Duration(minutes: 1));
      expect(resultats['l29']!.duree, const Duration(minutes: 5)); // 5e source du second lot
    });

    test('erreurs typées : 500, hors ligne, délai, code ≠ Ok, JSON invalide', () async {
      const logements = {'a': Coordonnees(lat: 36.83, lon: 10.17)};
      Future<void> verifier(MockClient client, Matcher attendu) => expectLater(
        TrajetService(databaseHelper: base, client: client, delai: const Duration(milliseconds: 50))
            .calculer(universite: _fac, logements: logements, mode: ModeTrajet.pied),
        throwsA(attendu),
      );
      await verifier(MockClient((_) async => http.Response('', 500)), isA<TrajetIndisponibleException>());
      await verifier(MockClient((_) async => throw const SocketException('hors ligne')), isA<TrajetIndisponibleException>());
      await verifier(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return _table([1], [1]);
        }),
        isA<TrajetIndisponibleException>(),
      );
      await verifier(MockClient((_) async => http.Response('{"code":"InvalidQuery"}', 200)), isA<TrajetReponseInvalideException>());
      await verifier(MockClient((_) async => http.Response('<html>', 200)), isA<TrajetReponseInvalideException>());
    });
  });

  group('TrajetProvider', () {
    /// Faux Nominatim + faux OSRM : la durée dépend de la latitude du logement.
    MockClient serveurs({Set<String> introuvables = const {}}) => MockClient((request) async {
      if (request.url.host == 'nominatim.openstreetmap.org') {
        final q = request.url.queryParameters['q']!;
        if (introuvables.contains(q)) return http.Response('[]', 200);
        final lat = q.contains('Proche') ? 36.840 : q.contains('Ariana') ? 36.860 : 36.800;
        return http.Response(jsonEncode([{'lat': '$lat', 'lon': '10.15', 'display_name': q}]), 200);
      }
      // OSRM : coordonnées « lon,lat;… » ; la première est l'université.
      final points = request.url.pathSegments.last.split(';').skip(1).map((c) => double.parse(c.split(',')[1])).toList();
      final pied = request.url.host == 'routing.openstreetmap.de';
      return _table(
        [for (final lat in points) lat == 36.84 ? (pied ? 600 : 180) : lat == 36.86 ? (pied ? 1500 : 400) : (pied ? 2700 : 600)],
        [for (final lat in points) lat == 36.84 ? 800 : lat == 36.86 ? 2000 : 4500],
      );
    });

    TrajetProvider provider(MockClient client) => TrajetProvider(
      trajets: TrajetService(databaseHelper: base, client: client),
      geocodage: GeocodageService(databaseHelper: base, client: client, pause: Duration.zero),
    );

    final annonces = [
      _logement('loin', adresse: '5 rue Loin', quartier: 'Bardo'),
      _logement('proche', adresse: '1 rue Proche', quartier: 'El Manar'),
      _logement('approx', adresse: 'Adresse inconnue', quartier: 'Ariana'),
      _logement('perdu', adresse: 'Nulle part'),
      Annonce(id: 'avis', categorie: 'Avis', titre: 'Coupure', description: 'd', statut: StatutAnnonce.publiee, proprietaireId: 'x'),
    ];

    test('durées à pied et en voiture, position approximative signalée, adresse introuvable', () async {
      final trajets = provider(serveurs(introuvables: {'Adresse inconnue, Ariana, Tunis', 'Nulle part, Tunis'}));
      addTearDown(trajets.dispose);
      trajets.definirUniversite(_facUniversite, annonces);
      await trajets.calculer(annonces); // déjà en cours : même signature, attend le premier calcul
      while (trajets.calculEnCours) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(trajets.pour('proche')!.pied!.duree, const Duration(minutes: 10));
      expect(trajets.pour('proche')!.voiture!.duree, const Duration(minutes: 3));
      expect(trajets.pour('approx')!.approximatif, isTrue);
      expect(trajets.pour('approx')!.pied!.duree, const Duration(minutes: 25));
      expect(trajets.pour('perdu')!.etat, EtatTrajet.nonLocalise);
      expect(trajets.pour('avis'), isNull); // pas un logement

      // Filtre « moins de 20 min à pied ».
      trajets.configurerFiltre(actif: true, minutes: 20, mode: ModeTrajet.pied);
      expect(trajets.appliquer(annonces).map((a) => a.id), ['proche']);
      // En voiture, 10 min : les trois logements localisés passent.
      trajets.configurerFiltre(minutes: 10, mode: ModeTrajet.voiture);
      expect(trajets.appliquer(annonces).map((a) => a.id), ['loin', 'proche', 'approx']);

      // Tri par distance : les inconnus à la fin, dans leur ordre d'origine.
      trajets.configurerFiltre(actif: false);
      trajets.basculerTri();
      expect(trajets.appliquer(annonces).map((a) => a.id), ['proche', 'approx', 'loin', 'perdu', 'avis']);
    });

    test('sans université : liste inchangée, aucun appel réseau', () async {
      var appels = 0;
      final trajets = provider(MockClient((_) async {
        appels++;
        return http.Response('[]', 200);
      }));
      addTearDown(trajets.dispose);
      await trajets.calculer(annonces);
      trajets.configurerFiltre(actif: true);
      expect(trajets.appliquer(annonces), annonces);
      expect(appels, 0);
    });

    test('hors ligne : erreur signalée, pas de nouvel essai automatique', () async {
      var appels = 0;
      final trajets = provider(MockClient((_) async {
        appels++;
        throw const SocketException('hors ligne');
      }));
      addTearDown(trajets.dispose);
      trajets.definirUniversite(_facUniversite, annonces);
      while (trajets.calculEnCours || appels == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(trajets.erreur, isNotNull);
      expect(trajets.pour('proche')!.etat, EtatTrajet.indisponible);
      final avant = appels;
      await trajets.calculer(annonces); // même liste : rien n'est relancé
      expect(appels, avant);
    });
  });

  group('Modèles', () {
    test('université enregistrée dans les préférences du profil', () {
      final preferences = {'notificationsEnabled': true, Universite.clePreference: _facUniversite.toMap()};
      expect(Universite.depuisPreferences(preferences), _facUniversite);
      expect(Universite.depuisPreferences(const {}), isNull);
      expect(Universite.depuisPreferences(const {'universite': 'texte'}), isNull);
    });

    test('formats de durée et de distance', () {
      expect(formatDuree(const Duration(seconds: 725)), '12 min');
      expect(formatDuree(const Duration(minutes: 65)), '1 h 05');
      expect(formatDistance(842), '840 m');
      expect(formatDistance(1234), '1,2 km');
    });
  });

  test('migration 12 → 13 : table trajets créée, données conservées', () async {
    final chemin = p.join(dossier.path, 'v12.db');
    final ancienne = await openDatabase(
      chemin,
      version: 12,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE geocodage (adresse TEXT PRIMARY KEY, lat REAL)');
        await db.insert('geocodage', {'adresse': 'el manar', 'lat': 36.84});
      },
    );
    await ancienne.close();
    final helper = DatabaseHelper.forTests(path: chemin);
    final db = await helper.database;
    expect(await db.getVersion(), DatabaseHelper.versionSchema);
    expect((await db.query('geocodage')).single['lat'], 36.84);
    final colonnes = (await db.rawQuery('PRAGMA table_info(trajets)')).map((c) => c['name']).toSet();
    expect(colonnes, {'depart', 'arrivee', 'mode', 'duree', 'distance', 'date'});
    await helper.fermer();
  });
}
