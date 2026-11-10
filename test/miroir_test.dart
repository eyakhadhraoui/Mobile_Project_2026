import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studenthub/services/api_client.dart';
import 'package:studenthub/services/database_helper.dart';
import 'package:studenthub/services/miroir_service.dart';

/// Serveur simulé : note ce qu'il reçoit et renvoie ce qu'on lui prépare.
class _Serveur extends ApiClient {
  final envois = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> lignes = const [];
  Map<String, dynamic> serveur = const {};
  bool enPanne = false;
  int revision = 1;
  List<int> refuses = const [];

  List<Map<String, dynamic>> get recus => [
    for (final envoi in envois) ...(envoi['changements'] as List).cast<Map<String, dynamic>>(),
  ];

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    if (enPanne) throw const ApiException('Serveur injoignable', code: 'network');
    envois.add(Map<String, dynamic>.from(body! as Map));
    return {'revision': ++revision, 'refuses': refuses, 'lignes': lignes, 'serveur': serveur};
  }
}

Map<String, Object?> _trajet(String id, {String auteur = 'moi', num places = 3, num? prix = 5.0}) => {
  'id': id,
  'auteurId': auteur,
  'auteurNom': 'A',
  'type': 'offre',
  'depart': 'Tunis',
  'arrivee': 'Sfax',
  'zone': 'Z',
  'date': '2026-12-01',
  'heure': '10:00',
  'places': places,
  'prix': prix,
  'commentaire': '',
  'statut': 'ouvert',
};

void main() {
  late Directory dossier;
  late DatabaseHelper base;
  late _Serveur serveur;
  late MiroirService service;
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('miroir_');
    base = DatabaseHelper.forTests(path: p.join(dossier.path, 'test.db'));
    serveur = _Serveur();
    service = MiroirService(client: serveur, databaseHelper: base);
    db = await base.database;
  });

  tearDown(() async {
    await db.close();
    await dossier.delete(recursive: true);
  });

  test('une ligne locale part une seule fois, tant qu’elle ne change pas', () async {
    await db.insert('covoiturage_trajets', _trajet('t1'));
    await service.synchroniser('moi');
    expect(serveur.recus.single['table'], 'covoiturage_trajets');
    expect((serveur.recus.single['ligne'] as Map)['depart'], 'Tunis');

    await service.synchroniser('moi');
    expect(serveur.recus, hasLength(1));

    await db.update('covoiturage_trajets', {'places': 2}, where: 'id = ?', whereArgs: ['t1']);
    await service.synchroniser('moi');
    expect(serveur.recus, hasLength(2));
    expect((serveur.recus.last['ligne'] as Map)['places'], 2);
  });

  test('une ligne refusée n’est pas renvoyée, mais reste disponible pour son propriétaire', () async {
    await db.insert('covoiturage_trajets', _trajet('t1', auteur: 'autre'));
    serveur.refuses = [0];
    await service.synchroniser('moi');
    expect(serveur.recus, hasLength(1));
    await service.synchroniser('moi');
    expect(serveur.recus, hasLength(1), reason: 'pas de nouvel essai pour ce compte');
    serveur.refuses = const [];
    await service.synchroniser('autre');
    expect(serveur.recus, hasLength(2), reason: 'envoyée quand son propriétaire se connecte');
  });

  test('une suppression locale est envoyée', () async {
    await db.insert('covoiturage_trajets', _trajet('t1'));
    await service.synchroniser('moi');
    await db.delete('covoiturage_trajets');
    await service.synchroniser('moi');
    expect(serveur.recus.last['ligne'], isNull);
    expect(serveur.recus.last['cle'], ['t1']);
  });

  test('une ligne reçue est écrite dans SQLite, sans être renvoyée', () async {
    serveur.lignes = [
      {'table': 'covoiturage_trajets', 'cle': ['t9'], 'ligne': _trajet('t9', auteur: 'autre')},
    ];
    expect(await service.synchroniser('moi'), 1);
    expect((await db.query('covoiturage_trajets')).single['auteurId'], 'autre');
    await service.synchroniser('moi');
    expect(serveur.recus, isEmpty);
  });

  test('un nombre rendu sans décimale par le JSON ne recrée pas de différence', () async {
    await db.insert('covoiturage_trajets', _trajet('t1', prix: 5.0));
    await service.synchroniser('moi');
    serveur.lignes = [
      {'table': 'covoiturage_trajets', 'cle': ['t1'], 'ligne': _trajet('t1', prix: 5)},
    ];
    expect(await service.synchroniser('moi'), 0);
    await service.synchroniser('moi');
    expect(serveur.recus, hasLength(1));
  });

  test('une suppression reçue retire la ligne', () async {
    serveur.lignes = [
      {'table': 'covoiturage_trajets', 'cle': ['t9'], 'ligne': _trajet('t9', auteur: 'autre')},
    ];
    await service.synchroniser('moi');
    serveur.lignes = [
      {'table': 'covoiturage_trajets', 'cle': ['t9'], 'ligne': null},
    ];
    await service.synchroniser('moi');
    expect(await db.query('covoiturage_trajets'), isEmpty);
    await service.synchroniser('moi');
    expect(serveur.recus, isEmpty);
  });

  test('une modification locale récente n’est pas écrasée', () async {
    serveur.lignes = [
      {'table': 'covoiturage_trajets', 'cle': ['t9'], 'ligne': _trajet('t9', places: 3)},
    ];
    await service.synchroniser('moi');
    await db.update('covoiturage_trajets', {'places': 1}, where: 'id = ?', whereArgs: ['t9']);
    serveur.lignes = [];
    final avecPanne = _trajet('t9', places: 3);
    serveur.lignes = [
      {'table': 'covoiturage_trajets', 'cle': ['t9'], 'ligne': avecPanne},
    ];
    await service.synchroniser('moi');
    expect(serveur.recus.last['ligne'], containsPair('places', 1));
  });

  test('la clé auto-incrémentée d’un historique ne voyage pas', () async {
    serveur.lignes = [
      {
        'table': 'demande_historique',
        'cle': ['d1', '2026', 'nouvelle'],
        'ligne': {'demandeId': 'd1', 'date': '2026', 'statut': 'nouvelle', 'auteurId': 'x'},
      },
    ];
    await service.synchroniser('moi');
    final lignes = await db.query('demande_historique');
    expect(lignes.single['demandeId'], 'd1');
    await service.synchroniser('moi');
    expect(await db.query('demande_historique'), hasLength(1));
    expect(serveur.recus, isEmpty);
  });

  test('une demande reçue est acceptée même si son auteur n’existe pas sur ce téléphone', () async {
    serveur.lignes = [
      {
        'table': 'demandes',
        'cle': ['d1'],
        'ligne': {
          'id': 'd1', 'userId': 'inconnu', 'category': 'c', 'room': 'r', 'urgency': 'u', 'title': 't', 'description': 'd',
          'residentName': 'n', 'residentPhone': 'p', 'statut': 's', 'createdAt': '2026',
        },
      },
    ];
    expect(await service.synchroniser('moi'), 1);
    expect(await db.query('demandes'), hasLength(1));
    expect((await db.rawQuery('PRAGMA foreign_keys')).single.values.single, 1, reason: 'contrôle réactivé');
  });

  test('une colonne inconnue du serveur est ignorée', () async {
    serveur.lignes = [
      {'table': 'covoiturage_trajets', 'cle': ['t1'], 'ligne': {..._trajet('t1'), 'colonne_pirate': 'x'}},
    ];
    expect(await service.synchroniser('moi'), 1);
    expect((await db.query('covoiturage_trajets')).single.containsKey('colonne_pirate'), isFalse);
  });

  test('les réglages et les comptes ne partent jamais', () async {
    await db.insert('app_settings', {'key': 'apiToken', 'value': 'secret'});
    await service.synchroniser('moi');
    expect(serveur.recus, isEmpty);
    expect(tablesMiroir.map((t) => t.nom), isNot(anyOf(contains('users'), contains('app_settings'))));
  });

  test('les envois sont découpés en lots', () async {
    for (var i = 0; i < 95; i++) {
      await db.insert('covoiturage_trajets', _trajet('t$i'));
    }
    await service.synchroniser('moi');
    expect(serveur.envois.map((e) => (e['changements'] as List).length), [40, 40, 15]);
  });

  test('sans réseau, rien n’est perdu', () async {
    await db.insert('covoiturage_trajets', _trajet('t1'));
    serveur.enPanne = true;
    await expectLater(service.synchroniser('moi'), throwsA(isA<ApiException>()));
    serveur.enPanne = false;
    await service.synchroniser('moi');
    expect(serveur.recus, hasLength(1));
  });

  group('données du serveur', () {
    Map<String, dynamic> visite(String id) => {
      'id': id, 'availabilityId': 'a', 'ownerId': 'o', 'clientId': 'c', 'propertyId': 'p', 'startAt': 's', 'endAt': 'e', 'status': 'confirmed', 'updatedAt': 'x',
    };

    test('les visites sont écrites dans SQLite', () async {
      serveur.serveur = {'visits': [visite('v1'), visite('v2')]};
      expect(await service.synchroniser('moi'), 2);
      expect(await db.query('visits'), hasLength(2));
      expect(await service.synchroniser('moi'), 0);
    });

    test('une ligne disparue du serveur est retirée, une ancienne ligne locale est gardée', () async {
      await db.insert('visits', visite('locale')..remove('updatedAt'));
      serveur.serveur = {'visits': [visite('v1')]};
      await service.synchroniser('moi');
      serveur.serveur = {'visits': <Map<String, dynamic>>[]};
      await service.synchroniser('moi');
      expect((await db.query('visits')).map((v) => v['id']), ['locale']);
    });

    test('les booléens et listes sont adaptés à SQLite', () async {
      serveur.serveur = {
        'visit_availability': [
          {'id': 'd', 'ownerId': 'o', 'startDate': 'a', 'endDate': 'b', 'startTime': 'c', 'endTime': 'e', 'durationMinutes': 30, 'breakMinutes': 0, 'active': true},
        ],
        'messagerie_messages': [
          {'id': 'm', 'conversationId': 'c', 'auteurId': 'a', 'texte': 't', 'photos': ['/photos/x.jpg'], 'langue': 'fr', 'createdAt': 'd'},
        ],
      };
      await service.synchroniser('moi');
      expect((await db.query('visit_availability')).single['active'], 1);
      expect((await db.query('messagerie_messages')).single['photos'], '["/photos/x.jpg"]');
    });
  });
}
