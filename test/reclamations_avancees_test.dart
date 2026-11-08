import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studenthub/core/utils/detecteur_danger.dart';
import 'package:studenthub/core/utils/texte.dart';
import 'package:studenthub/models/complaint_model.dart';
import 'package:studenthub/services/database_helper.dart';
import 'package:studenthub/services/geocodage_service.dart';
import 'package:studenthub/services/incident_service.dart';
import 'package:studenthub/services/tri_reclamation_service.dart';

final _serveur = Uri.parse('http://10.0.2.2:6500');

/// Réponse de la route /chat contenant le texte [reply].
http.Response _chat(String reply) => http.Response.bytes(utf8.encode(jsonEncode({'reply': reply})), 200);

ComplaintModel _reclamation(
  String id, {
  String lieu = 'Résidence El Manar, Bloc A, appt 12',
  ComplaintCategory categorie = ComplaintCategory.fuiteEau,
  required DateTime date,
  String auteur = 'etu1',
  ComplaintStatus statut = ComplaintStatus.ouverte,
  ComplaintPriority priorite = ComplaintPriority.moyenne,
  bool brouillon = false,
}) => ComplaintModel(
  id: id,
  userId: auteur,
  locationId: lieu,
  subject: 'Sujet $id',
  category: categorie,
  description: 'Description',
  photos: const [],
  status: statut,
  priority: priorite,
  createdAt: date,
  isDraft: brouillon,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Détection locale des dangers', () {
    test('gaz, étincelles, inondation reconnus malgré accents et majuscules', () {
      expect(detecterDangers('Forte ODEUR DE GAZ dans la cuisine').single.type, TypeDanger.gaz);
      expect(detecterDangers('La prise fait des Étincelles').single.type, TypeDanger.electrique);
      expect(detecterDangers('Salle de bain inondée, l’eau déborde').single.type, TypeDanger.inondation);
      expect(detecterDangers('Le plafond menace de tomber').single.type, TypeDanger.structure);
      expect(detecterDangers('De la fumée sort du compteur').map((d) => d.type), contains(TypeDanger.incendie));
    });

    test('pas de faux danger sur un texte ordinaire', () {
      expect(detecterDangers('Le robinet goutte un peu et la porte grince.'), isEmpty);
      expect(detecterDangers('Je voudrais un gazon dans le jardin'), isEmpty); // « gazon » ≠ « gaz »
    });

    test('chaque danger a des consignes et une catégorie évidente si elle existe', () {
      for (final type in TypeDanger.values) {
        expect(consignesSecurite[type], isNotEmpty);
      }
      expect(detecterDangers('court-circuit').single.categorie, ComplaintCategory.electricite);
      expect(detecterDangers('inondation').single.categorie, ComplaintCategory.fuiteEau);
    });

    test('données personnelles masquées', () {
      final masque = masquerDonneesPersonnelles('Appelez-moi au +216 22 333 444 ou sami.benali@univ.tn');
      expect(masque, isNot(contains('22 333 444')));
      expect(masque, isNot(contains('sami.benali')));
      expect(masque, contains('[téléphone masqué]'));
      expect(masque, contains('[e-mail masqué]'));
    });
  });

  group('Tri par IA (route /chat)', () {
    test('JSON valide (même dans un bloc de code) : catégorie, priorité, résumé', () async {
      late Map<String, dynamic> corps;
      final service = TriReclamationService(
        serveur: _serveur,
        client: MockClient((request) async {
          expect(request.url.toString(), 'http://10.0.2.2:6500/chat');
          corps = jsonDecode(request.body) as Map<String, dynamic>;
          return _chat('```json\n{"categorie":"chauffage","priorite":"moyenne","resume":"Radiateur froid dans la chambre","danger":false}\n```');
        }),
      );
      final suggestion = await service.analyser(titre: '', description: 'Le radiateur reste froid depuis hier.');
      expect(suggestion.categorie, ComplaintCategory.chauffage);
      expect(suggestion.priorite, ComplaintPriority.moyenne);
      expect(suggestion.resume, 'Radiateur froid dans la chambre');
      expect(suggestion.danger, isFalse);
      expect(corps.keys, ['messages']);
    });

    test('danger local : urgente imposée même si l’IA répond « faible »', () async {
      final service = TriReclamationService(
        serveur: _serveur,
        client: MockClient((_) async => _chat('{"categorie":"equipement","priorite":"faible","resume":"Prise abîmée","danger":false}')),
      );
      final suggestion = await service.analyser(titre: 'Prise', description: 'La prise fait des étincelles quand je branche.');
      expect(suggestion.priorite, ComplaintPriority.urgente);
      expect(suggestion.categorie, ComplaintCategory.electricite);
      expect(suggestion.dangers.single.type, TypeDanger.electrique);
    });

    test('catégorie inconnue ignorée, résumé tronqué à 60 caractères', () {
      final suggestion = TriReclamationService.interpreter(
        '{"categorie":"piscine","priorite":"urgente","resume":"${'x' * 80}","danger":true}',
      );
      expect(suggestion.categorie, isNull);
      expect(suggestion.priorite, ComplaintPriority.urgente);
      expect(suggestion.resume.length, lessThanOrEqualTo(60));
      expect(suggestion.dangerSignaleParIa, isTrue);
    });

    test('réponse sans JSON exploitable → TriReponseInvalideException', () {
      expect(() => TriReclamationService.interpreter('Je pense que c’est une fuite.'), throwsA(isA<TriReponseInvalideException>()));
      expect(() => TriReclamationService.interpreter('{"autre": 1}'), throwsA(isA<TriReponseInvalideException>()));
    });

    test('serveur 503, 500, hors ligne, délai dépassé → TriIndisponibleException', () async {
      final cas = [
        MockClient((_) async => http.Response('{"error":"assistant_not_configured"}', 503)),
        MockClient((_) async => http.Response('', 500)),
        MockClient((_) async => throw const SocketException('hors ligne')),
        MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return _chat('{}');
        }),
      ];
      for (final client in cas) {
        final service = TriReclamationService(serveur: _serveur, client: client, delai: const Duration(milliseconds: 50));
        await expectLater(service.analyser(titre: 't', description: 'Fuite sous l’évier.'), throwsA(isA<TriIndisponibleException>()));
      }
    });

    test('aucune donnée personnelle envoyée', () async {
      late String contenu;
      final service = TriReclamationService(
        serveur: _serveur,
        client: MockClient((request) async {
          contenu = request.body;
          expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
          return _chat('{"categorie":"fuiteEau","priorite":"moyenne","resume":"Fuite","danger":false}');
        }),
      );
      await service.analyser(titre: 'Fuite', description: 'Fuite sous l’évier. Mon numéro : 22 333 444, mail sami@univ.tn');
      expect(contenu, isNot(contains('22 333 444')));
      expect(contenu, isNot(contains('sami@univ.tn')));
    });
  });

  group('Géocodage (Nominatim)', () {
    late Directory dossier;
    late DatabaseHelper base;
    setUp(() async {
      dossier = await Directory.systemTemp.createTemp('studenthub_geo_');
      base = DatabaseHelper.forTests(path: p.join(dossier.path, 'studenthub.db'));
    });
    tearDown(() async {
      await base.fermer();
      await dossier.delete(recursive: true);
    });

    test('coordonnées lues, cache utilisé au second appel, règles d’usage respectées', () async {
      final requetes = <http.Request>[];
      final service = GeocodageService(
        databaseHelper: base,
        pause: Duration.zero,
        client: MockClient((request) async {
          requetes.add(request);
          return http.Response.bytes(
            utf8.encode(jsonEncode([
              {'lat': '36.8421', 'lon': '10.1971', 'display_name': 'El Manar, Tunis, Tunisie'},
            ])),
            200,
          );
        }),
      );
      final premier = await service.geocoder('Résidence El Manar, Tunis');
      final second = await service.geocoder('residence el manar tunis'); // même adresse normalisée
      expect(premier!.lat, 36.8421);
      expect(second!.lon, 10.1971);
      expect(requetes, hasLength(1));
      final requete = requetes.single;
      expect(requete.url.host, 'nominatim.openstreetmap.org');
      expect(requete.url.queryParameters['q'], 'Résidence El Manar, Tunis');
      expect(requete.url.queryParameters['format'], 'jsonv2');
      expect(requete.headers['User-Agent'], startsWith('StudentHub/'));
      expect(requete.headers['User-Agent'], isNot(contains('@')));
    });

    test('adresse introuvable mise en cache (pas de nouvel appel)', () async {
      var appels = 0;
      final service = GeocodageService(
        databaseHelper: base,
        pause: Duration.zero,
        client: MockClient((_) async {
          appels++;
          return http.Response('[]', 200);
        }),
      );
      expect(await service.geocoder('Bloc Z chambre 404'), isNull);
      expect(await service.geocoder('Bloc Z chambre 404'), isNull);
      expect(appels, 1);
    });

    test('panne réseau : géocodage partiel signalé, positions déjà trouvées conservées', () async {
      var appels = 0;
      final service = GeocodageService(
        databaseHelper: base,
        pause: Duration.zero,
        client: MockClient((_) async {
          if (++appels > 1) throw const SocketException('hors ligne');
          return http.Response('[{"lat":"36.8","lon":"10.1","display_name":"A"}]', 200);
        }),
      );
      final resultat = await service.geocoderTout(['Adresse A', 'Adresse B', 'Adresse A']);
      expect(resultat.incomplet, isTrue);
      expect(resultat.positions[GeocodageService.cle('Adresse A')]!.lat, 36.8);
      expect(resultat.positions.containsKey(GeocodageService.cle('Adresse B')), isFalse);
    });

    test('statut 503 → GeocodageIndisponibleException', () {
      final service = GeocodageService(databaseHelper: base, pause: Duration.zero, client: MockClient((_) async => http.Response('', 503)));
      expect(service.geocoder('Tunis'), throwsA(isA<GeocodageIndisponibleException>()));
    });

    test('une requête par seconde au plus', () async {
      final instants = <DateTime>[];
      final service = GeocodageService(
        databaseHelper: base,
        pause: const Duration(milliseconds: 200),
        client: MockClient((_) async {
          instants.add(DateTime.now());
          return http.Response('[]', 200);
        }),
      );
      await service.geocoderTout(['A', 'B']);
      expect(instants[1].difference(instants[0]).inMilliseconds, greaterThanOrEqualTo(190));
    });
  });

  group('Incidents collectifs', () {
    final t0 = DateTime(2026, 11, 6, 9);

    test('même bâtiment (appartements différents), même catégorie, moins de 48 h → un incident', () {
      final incidents = IncidentService.regrouper([
        _reclamation('a', date: t0, lieu: 'Résidence El Manar, Bloc A, appt 12', auteur: 'etu1'),
        _reclamation('b', date: t0.add(const Duration(hours: 20)), lieu: 'residence el manar - bloc A app. 14', auteur: 'etu2'),
        _reclamation('c', date: t0.add(const Duration(hours: 60)), lieu: 'Résidence El Manar Bloc A chambre 3', auteur: 'etu3'),
      ]);
      expect(incidents, hasLength(1));
      expect(incidents.single.reclamations.map((r) => r.id), ['a', 'b', 'c']); // écarts successifs ≤ 48 h
      expect(incidents.single.nombreEtudiants, 3);
      expect(incidents.single.id, 'a');
    });

    test('écart de plus de 48 h, autre catégorie, autre bâtiment : pas de regroupement', () {
      final incidents = IncidentService.regrouper([
        _reclamation('a', date: t0),
        _reclamation('b', date: t0.add(const Duration(hours: 49))),
        _reclamation('c', date: t0.add(const Duration(hours: 1)), categorie: ComplaintCategory.electricite),
        _reclamation('d', date: t0.add(const Duration(hours: 2)), lieu: 'Résidence El Manar, Bloc B, appt 2'),
      ]);
      expect(incidents, isEmpty);
    });

    test('réclamations résolues et brouillons ignorés, priorité la plus haute retenue', () {
      final incidents = IncidentService.regrouper([
        _reclamation('a', date: t0, priorite: ComplaintPriority.faible),
        _reclamation('b', date: t0.add(const Duration(hours: 1)), priorite: ComplaintPriority.urgente),
        _reclamation('c', date: t0.add(const Duration(hours: 2)), statut: ComplaintStatus.cloturee),
        _reclamation('d', date: t0.add(const Duration(hours: 3)), brouillon: true),
      ]);
      expect(incidents.single.reclamations.map((r) => r.id), ['a', 'b']);
      expect(incidents.single.priorite, ComplaintPriority.urgente);
      expect(incidents.single.contient('b'), isTrue);
      expect(incidents.single.contient('c'), isFalse);
    });

    test('clé de bâtiment sans numéro d’appartement', () {
      expect(IncidentService.cleBatiment('Résidence El-Manar, Bloc A, Appt 12'), 'residence el manar bloc a');
      expect(IncidentService.cleBatiment('Bloc A étage 3 porte 7b'), 'bloc a');
    });
  });

  group('Migration SQLite (version 11 → 12)', () {
    test('table geocodage créée, données conservées', () async {
      final dossier = await Directory.systemTemp.createTemp('studenthub_v11_');
      addTearDown(() => dossier.delete(recursive: true));
      final chemin = p.join(dossier.path, 'v11.db');
      final ancienne = await openDatabase(
        chemin,
        version: 11,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE complaints (id TEXT PRIMARY KEY, locationId TEXT NOT NULL)');
          await db.insert('complaints', {'id': 'c1', 'locationId': 'Bloc A'});
        },
      );
      await ancienne.close();
      final helper = DatabaseHelper.forTests(path: chemin);
      final db = await helper.database;
      expect(await db.getVersion(), DatabaseHelper.versionSchema);
      expect((await db.query('complaints')).single['locationId'], 'Bloc A');
      final colonnes = (await db.rawQuery('PRAGMA table_info(geocodage)')).map((c) => c['name']).toSet();
      expect(colonnes, {'adresse', 'lat', 'lon', 'libelle', 'introuvable', 'date'});
      await helper.fermer();
    });
  });
}
