import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studenthub/models/complaint_response_model.dart';
import 'package:studenthub/providers/traduction_provider.dart';
import 'package:studenthub/services/complaint_service.dart';
import 'package:studenthub/services/database_helper.dart';
import 'package:studenthub/services/traduction_service.dart';

/// Réponse MyMemory réussie.
http.Response _myMemory(String traduction, {Object status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode({
    'responseData': {'translatedText': traduction, 'match': 1},
    'responseStatus': status,
    'matches': [],
  })),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

ComplaintResponse _reponse({String id = 'r1', String texte = 'Le plombier passe demain.', String auteur = 'proprio'}) =>
    ComplaintResponse(
      id: id,
      complaintId: 'c1',
      authorId: auteur,
      authorRole: ComplaintAuthorRole.proprietaire,
      text: texte,
      langue: 'fr',
      createdAt: DateTime.utc(2026, 11, 6),
    );

void main() {
  late Directory dossier;
  late DatabaseHelper base;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('studenthub_traduction_');
    base = DatabaseHelper.forTests(path: p.join(dossier.path, 'studenthub.db'));
  });

  tearDown(() async {
    await base.fermer();
    await dossier.delete(recursive: true);
  });

  TraductionService service(MockClient client, {Uri? serveur, Duration? delai}) => TraductionService(
    client: client,
    databaseHelper: base,
    serveur: serveur,
    utiliserServeur: serveur != null,
    delai: delai ?? const Duration(seconds: 8),
  );

  group('TraductionService', () {
    test('traduction correcte fr → ru (MyMemory)', () async {
      late Uri appelee;
      final traducteur = service(MockClient((request) async {
        appelee = request.url;
        return _myMemory('Сантехник придёт завтра.');
      }));
      expect(await traducteur.traduire('Le plombier passe demain.', de: 'fr', vers: 'ru'), 'Сантехник придёт завтра.');
      expect(appelee.scheme, 'https');
      expect(appelee.host, 'api.mymemory.translated.net');
      expect(appelee.path, '/get');
      expect(appelee.queryParameters, {'q': 'Le plombier passe demain.', 'langpair': 'fr|ru'});
    });

    test('texte long : plusieurs appels de 400 caractères maximum, recollés dans l’ordre', () async {
      final phrases = [
        for (var i = 1; i <= 5; i++) 'Phrase numéro $i ${'x' * 150}.',
      ];
      final envoyes = <String>[];
      final traducteur = service(MockClient((request) async {
        final q = request.url.queryParameters['q']!;
        envoyes.add(q);
        return _myMemory('[$q]');
      }));
      final resultat = await traducteur.traduire('${phrases.join(' ')}\nDeuxième paragraphe.', de: 'fr', vers: 'en');

      expect(envoyes.length, greaterThan(1));
      expect(envoyes.every((q) => q.length <= 400), isTrue);
      // Ordre conservé et aucun texte perdu.
      expect(envoyes.join(' '), '${phrases.join(' ')} Deuxième paragraphe.');
      expect(resultat, '${envoyes.take(envoyes.length - 1).map((q) => '[$q]').join(' ')}\n[Deuxième paragraphe.]');
    });

    test('découpage aux fins de phrases, sans couper « 3.5 », mot géant coupé', () {
      expect(TraductionService.decouper('Loyer de 3.5 mille. Merci !', max: 15), ['Loyer de 3.5', 'mille. Merci !']);
      final geant = 'a' * 950;
      final morceaux = TraductionService.decouper(geant);
      expect(morceaux.every((m) => m.length <= 400), isTrue);
      expect(morceaux.join(), geant);
      // Alphabet cyrillique : limite en octets (2 octets par lettre).
      final russe = List.filled(60, 'Привет мир.').join(' ');
      expect(TraductionService.decouper(russe).every((m) => utf8.encode(m).length <= TraductionService.octetsMaxMorceau), isTrue);
    });

    test('cache SQLite utilisé au second appel', () async {
      var appels = 0;
      final traducteur = service(MockClient((_) async {
        appels++;
        return _myMemory('The plumber comes tomorrow.');
      }));
      for (var i = 0; i < 2; i++) {
        expect(
          await traducteur.traduireReponse(reponseId: 'r1', texte: 'Le plombier passe demain.', de: 'fr', vers: 'en'),
          'The plumber comes tomorrow.',
        );
      }
      expect(appels, 1);
      final lignes = await (await base.database).query('traductions');
      expect(lignes.single['reponse_id'], 'r1');
      expect(lignes.single['langue'], 'en');
    });

    test('statut 500 → TraductionIndisponibleException', () {
      final traducteur = service(MockClient((_) async => http.Response('erreur', 500)));
      expect(traducteur.traduire('Bonjour.', de: 'fr', vers: 'ru'), throwsA(isA<TraductionIndisponibleException>()));
    });

    test('délai dépassé → TraductionIndisponibleException', () {
      final traducteur = service(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return _myMemory('trop tard');
        }),
        delai: const Duration(milliseconds: 50),
      );
      expect(traducteur.traduire('Bonjour.', de: 'fr', vers: 'ru'), throwsA(isA<TraductionIndisponibleException>()));
    });

    test('hors ligne (SocketException) → TraductionIndisponibleException', () {
      final traducteur = service(MockClient((_) async => throw const SocketException('hors ligne')));
      expect(traducteur.traduire('Bonjour.', de: 'fr', vers: 'ru'), throwsA(isA<TraductionIndisponibleException>()));
    });

    test('JSON inattendu ou responseStatus ≠ 200 → exceptions typées', () async {
      expect(
        service(MockClient((_) async => http.Response('{"foo": 1}', 200))).traduire('Bonjour.', de: 'fr', vers: 'ru'),
        throwsA(isA<TraductionReponseInvalideException>()),
      );
      expect(
        service(MockClient((_) async => http.Response('<html>', 200))).traduire('Bonjour.', de: 'fr', vers: 'ru'),
        throwsA(isA<TraductionReponseInvalideException>()),
      );
      expect(
        service(MockClient((_) async => _myMemory('MYMEMORY WARNING: QUOTA', status: '429'))).traduire('Bonjour.', de: 'fr', vers: 'ru'),
        throwsA(isA<TraductionRefuseeException>()),
      );
    });

    test('repli sur /chat du serveur quand MyMemory échoue', () async {
      Map<String, dynamic>? corps;
      final traducteur = service(
        MockClient((request) async {
          if (request.url.host == 'api.mymemory.translated.net') return http.Response('panne', 503);
          expect(request.url.toString(), 'http://10.0.2.2:6500/chat');
          expect(request.method, 'POST');
          corps = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(utf8.encode(jsonEncode({'reply': 'Сантехник придёт завтра.'})), 200);
        }),
        serveur: Uri.parse('http://10.0.2.2:6500'),
      );
      expect(await traducteur.traduire('Le plombier passe demain.', de: 'fr', vers: 'ru'), 'Сантехник придёт завтра.');
      final contenu = (corps!['messages'] as List).single['content'] as String;
      expect(corps!.keys, ['messages']);
      expect(contenu, contains('du français vers le russe'));
      expect(contenu, contains('uniquement par la traduction'));
      expect(contenu, endsWith('Le plombier passe demain.'));
    });

    test('la requête ne contient aucune donnée personnelle', () async {
      final requetes = <http.Request>[];
      final traducteur = service(
        MockClient((request) async {
          requetes.add(request);
          return request.url.host == 'api.mymemory.translated.net'
              ? http.Response('panne', 500)
              : http.Response(jsonEncode({'reply': 'ok'}), 200);
        }),
        serveur: Uri.parse('https://studenthub.example'),
      );
      await traducteur.traduireReponse(
        reponseId: 'reponse-etudiant42@univ.tn',
        texte: 'Bonjour.',
        de: 'fr',
        vers: 'en',
      );
      final myMemory = requetes.first;
      expect(myMemory.url.queryParameters.keys.toSet(), {'q', 'langpair'}); // pas de paramètre « de » (e-mail)
      for (final requete in requetes) {
        final tout = '${requete.url} ${requete.headers} ${requete.body}';
        expect(tout, isNot(contains('@')));
        expect(tout, isNot(contains('etudiant42')));
        expect(requete.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
        expect(requete.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cookie')));
      }
    });

    test('même langue : aucun appel', () async {
      var appels = 0;
      final traducteur = service(MockClient((_) async {
        appels++;
        return _myMemory('x');
      }));
      expect(await traducteur.traduire('Bonjour.', de: 'fr', vers: 'fr'), 'Bonjour.');
      expect(appels, 0);
    });

    test('entités HTML décodées', () {
      expect(TraductionService.decoderEntites('l&#39;eau &quot;chaude&quot; &amp; froide'), 'l\'eau "chaude" & froide');
    });
  });

  group('TraductionProvider', () {
    test('traduire, basculer Original / Traduction, ignorer ses propres messages', () async {
      final provider = TraductionProvider(
        service: service(MockClient((_) async => _myMemory('Сантехник придёт завтра.'))),
        langueCible: 'ru',
        lecteurId: 'etudiant',
      );
      addTearDown(provider.dispose);
      provider.definirReponses([_reponse(), _reponse(id: 'moi', auteur: 'etudiant')]);
      expect(provider.peutTraduire(_reponse()), isTrue);
      expect(provider.peutTraduire(_reponse(id: 'moi', auteur: 'etudiant')), isFalse);

      final enCours = provider.traduireReponse('r1');
      expect(provider.etat('r1').etat, EtatTraduction.loading);
      await enCours;
      expect(provider.etat('r1').etat, EtatTraduction.traduit);
      expect(provider.etat('r1').texte, 'Сантехник придёт завтра.');
      expect(provider.etat('r1').afficherTraduction, isTrue);
      provider.basculerAffichage('r1');
      expect(provider.etat('r1').afficherTraduction, isFalse);

      // Message modifié : la traduction précédente est oubliée.
      provider.definirReponses([_reponse(texte: 'Le plombier passe lundi.')]);
      expect(provider.etat('r1').etat, EtatTraduction.idle);
    });

    test('erreur : état « erreur », le texte original reste disponible', () async {
      final provider = TraductionProvider(
        service: service(MockClient((_) async => http.Response('', 500))),
        langueCible: 'ru',
        lecteurId: 'etudiant',
      );
      addTearDown(provider.dispose);
      provider.definirReponses([_reponse()]);
      await provider.traduireReponse('r1');
      expect(provider.etat('r1').etat, EtatTraduction.erreur);
      expect(provider.etat('r1').texte, isNull);
    });

    test('écran fermé pendant la traduction : résultat ignoré sans erreur', () async {
      final reponse = Completer<http.Response>();
      final provider = TraductionProvider(
        service: service(MockClient((_) => reponse.future)),
        langueCible: 'ru',
        lecteurId: 'etudiant',
      );
      provider.definirReponses([_reponse()]);
      final enCours = provider.traduireReponse('r1');
      provider.dispose();
      reponse.complete(_myMemory('Сантехник'));
      await enCours; // aucun notifyListeners après dispose
    });
  });

  group('Migration SQLite (version 10 → 11)', () {
    test('colonne langue et table traductions créées, données conservées', () async {
      final chemin = p.join(dossier.path, 'v10.db');
      final ancienne = await openDatabase(
        chemin,
        version: 10,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE users (
              id TEXT PRIMARY KEY, nom TEXT NOT NULL, prenom TEXT NOT NULL,
              email TEXT NOT NULL UNIQUE COLLATE NOCASE, telephone TEXT NOT NULL UNIQUE,
              rolePrincipal TEXT NOT NULL, roleSecondaire TEXT, photo TEXT,
              preferences TEXT NOT NULL DEFAULT '{}', passwordHash TEXT NOT NULL,
              passwordSalt TEXT NOT NULL, createdAt TEXT NOT NULL,
              emailVerified INTEGER NOT NULL DEFAULT 0,
              accountStatus TEXT NOT NULL DEFAULT 'pending', isRemote INTEGER NOT NULL DEFAULT 0
            )''');
          await db.insert('users', {
            'id': 'u1', 'nom': 'Ben Ali', 'prenom': 'Sami', 'email': 'sami@test.tn', 'telephone': '20000000',
            'rolePrincipal': 'locataire', 'passwordHash': 'h', 'passwordSalt': 's', 'createdAt': '2026-01-01T00:00:00Z',
          });
        },
      );
      await ancienne.close();

      final helper = DatabaseHelper.forTests(path: chemin);
      final db = await helper.database;
      expect(await db.getVersion(), DatabaseHelper.versionSchema);
      final utilisateur = (await db.query('users')).single;
      expect(utilisateur['prenom'], 'Sami');
      expect(utilisateur['email'], 'sami@test.tn');
      expect(utilisateur['langue'], 'fr');

      final colonnes = (await db.rawQuery('PRAGMA table_info(traductions)')).map((c) => c['name']).toSet();
      expect(colonnes, {'id', 'reponse_id', 'langue', 'texte_traduit', 'date'});
      await db.insert('traductions', {'reponse_id': 'r1', 'langue': 'ru', 'texte_traduit': 'a', 'date': 'd'});
      // Clé unique (reponse_id, langue).
      expect(
        () => db.insert('traductions', {'reponse_id': 'r1', 'langue': 'ru', 'texte_traduit': 'b', 'date': 'd'}),
        throwsA(isA<DatabaseException>()),
      );
      expect((await db.rawQuery('PRAGMA table_info(complaint_responses)')).map((c) => c['name']), contains('langue'));
      await helper.fermer();
    });
  });

  group('ComplaintService : cache des traductions invalidé', () {
    // ComplaintService utilise la base principale : ici celle de sqflite_common_ffi.
    late String chemin;
    setUp(() async {
      chemin = p.join(await getDatabasesPath(), 'studenthub.db');
      await DatabaseHelper.instance.fermer();
      await deleteDatabase(chemin);
    });
    tearDown(() async {
      await DatabaseHelper.instance.fermer();
      await deleteDatabase(chemin);
    });

    test('modification puis suppression d’une réponse : traductions supprimées', () async {
      final complaints = ComplaintService();
      final reponse = await complaints.addResponse(
        complaintId: 'c1',
        authorId: 'proprio',
        authorRole: ComplaintAuthorRole.proprietaire,
        text: 'Le plombier passe demain.',
        langue: 'fr',
      );
      final db = await DatabaseHelper.instance.database;
      Future<int> nbTraductions() async => (await db.query('traductions', where: 'reponse_id = ?', whereArgs: [reponse.id])).length;
      Future<void> traduire() => db.insert('traductions', {'reponse_id': reponse.id, 'langue': 'ru', 'texte_traduit': 't', 'date': 'd'});

      await traduire();
      // Un autre utilisateur ne peut pas modifier ce message : le cache reste.
      await complaints.updateResponse(reponse.id, 'Piraté', authorId: 'quelquun');
      expect(await nbTraductions(), 1);

      await complaints.updateResponse(reponse.id, 'Le plombier passe lundi.', authorId: 'proprio');
      expect(await nbTraductions(), 0);
      expect((await complaints.getResponses('c1')).single.text, 'Le plombier passe lundi.');

      await traduire();
      await complaints.deleteResponse(reponse.id, authorId: 'proprio');
      expect(await nbTraductions(), 0);
      expect(await complaints.getResponses('c1'), isEmpty);
    });
  });
}
