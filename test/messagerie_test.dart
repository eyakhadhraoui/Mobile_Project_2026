import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studenthub/models/messagerie.dart';
import 'package:studenthub/providers/messagerie_provider.dart';
import 'package:studenthub/providers/traduction_provider.dart';
import 'package:studenthub/screens/messagerie/discussion_screen.dart';
import 'package:studenthub/services/api_client.dart';
import 'package:studenthub/services/database_helper.dart';
import 'package:studenthub/services/messagerie_service.dart';
import 'package:studenthub/services/photo_storage.dart';
import 'package:studenthub/services/traduction_service.dart';

const _reseau = ApiException('Serveur injoignable', code: 'network');

Map<String, dynamic> _json(String id, String auteur, String texte, {String langue = 'fr', String? clientId}) => {
  'id': id,
  'auteurId': auteur,
  'texte': texte,
  'photos': const <String>[],
  'langue': langue,
  'clientId': clientId,
  'createdAt': '2026-11-09T10:00:00.000Z',
};

/// Serveur simulé : hors ligne tant que [enPanne] est vrai.
class _Client extends ApiClient {
  bool enPanne = false;
  ApiException? refus;
  final fil = <Map<String, dynamic>>[];
  final envois = <Map<String, dynamic>>[];
  final televersees = <String>[];
  int lectures304 = 0;

  void _verifier() {
    if (enPanne) throw _reseau;
  }

  @override
  Future<dynamic> getAvecCache(String path) async {
    _verifier();
    return {'messages': List.of(fil)};
  }

  @override
  Future<ApiResponse> getSiModifie(String path, String? etag) async {
    _verifier();
    final courant = '"${fil.length}"';
    if (etag == courant) {
      lectures304++;
      return ApiResponse(304, null, etag);
    }
    return ApiResponse(200, {'messages': List.of(fil)}, courant);
  }

  @override
  Future<String> uploadPhoto(String filePath) async {
    _verifier();
    televersees.add(filePath);
    return '/photos/${'a' * 32}.jpg';
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    _verifier();
    if (refus case final erreur?) throw erreur;
    final corps = Map<String, dynamic>.from(body! as Map);
    envois.add(corps);
    final message = _json('s${fil.length}', 'moi', corps['texte'] as String, clientId: corps['clientId'] as String);
    fil.add(message);
    return message;
  }
}

class _Traduction extends TraductionService {
  _Traduction() : super(utiliserServeur: false);
  int appels = 0;
  bool enPanne = false;

  @override
  Future<String> traduireReponse({required String reponseId, required String texte, required String de, required String vers}) async {
    appels++;
    if (enPanne) throw const TraductionIndisponibleException('panne');
    return '[$de→$vers] $texte';
  }
}

void main() {
  late Directory dossier;
  late DatabaseHelper base;
  late _Client client;
  late MessagerieService service;
  late _Traduction traduction;

  DiscussionProvider discussion() => DiscussionProvider(
    conversationId: 'c1',
    userId: 'moi',
    langueCible: 'fr',
    service: service,
    traduction: traduction,
    periode: Duration.zero,
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('messagerie_');
    base = DatabaseHelper.forTests(path: p.join(dossier.path, 'test.db'));
    client = _Client();
    traduction = _Traduction();
    service = MessagerieService(
      client: client,
      databaseHelper: base,
      stockage: PhotoStorage(documentsDirectory: () async => dossier),
    );
  });

  tearDown(() async {
    await (await base.database).close();
    await dossier.delete(recursive: true);
  });

  group('langue du message', () {
    test('l’écriture du texte prime sur le profil', () {
      expect(langueDuTexte('مرحبا هل الشقة متاحة', 'fr'), 'ar');
      expect(langueDuTexte('Привет', 'fr'), 'ru');
      expect(langueDuTexte('Hello', 'en'), 'en');
    });

    test('un profil arabe qui écrit en lettres latines n’est pas pris pour de l’arabe', () {
      expect(langueDuTexte('Bonjour', 'ar'), 'fr');
    });
  });

  group('envoi hors connexion', () {
    test('le message attend, survit à la fermeture et part une seule fois', () async {
      client.enPanne = true;
      final avant = discussion();
      await avant.demarrer();
      await avant.envoyer('Toujours disponible ?', const [], langueProfil: 'fr');
      expect(avant.horsLigne, isTrue);
      expect(avant.messages.single.etat, EtatEnvoi.enAttente);
      avant.dispose();

      client.enPanne = false;
      final apres = discussion();
      await apres.demarrer();
      expect(client.envois, hasLength(1));
      expect(client.envois.single['texte'], 'Toujours disponible ?');
      expect(apres.horsLigne, isFalse);
      expect(apres.messages.single.etat, EtatEnvoi.envoye);

      await apres.actualiser();
      expect(client.envois, hasLength(1), reason: 'pas de second envoi');
      apres.dispose();
    });

    test('la photo est copiée, envoyée puis effacée du téléphone', () async {
      final source = File(p.join(dossier.path, 'prise.jpg'))..writeAsBytesSync([1, 2, 3]);
      client.enPanne = true;
      final d = discussion();
      await d.demarrer();
      await d.envoyer('', [source.path], langueProfil: 'fr');
      final copie = d.messages.single.photos.single;
      expect(copie, isNot(source.path));
      expect(File(copie).existsSync(), isTrue);

      client.enPanne = false;
      await d.actualiser();
      expect(client.televersees, [copie]);
      expect(client.envois.single['photos'], ['/photos/${'a' * 32}.jpg']);
      expect(File(copie).existsSync(), isFalse);
      d.dispose();
    });

    test('un refus du serveur s’affiche et le message peut être supprimé', () async {
      client.refus = const ApiException('Conversation introuvable.', status: 404, code: 'not_found');
      final d = discussion();
      await d.demarrer();
      await d.envoyer('Bonjour', const [], langueProfil: 'fr');
      final echec = d.messages.single;
      expect(echec.etat, EtatEnvoi.echec);
      expect(echec.erreur, 'Conversation introuvable.');
      await d.abandonner(echec.id);
      expect(d.messages, isEmpty);
      d.dispose();
    });

    test('une panne du serveur laisse le message en attente', () async {
      client.refus = const ApiException('Erreur interne', status: 500, code: 'server_error');
      final d = discussion();
      await d.demarrer();
      await d.envoyer('Bonjour', const [], langueProfil: 'fr');
      expect(d.messages.single.etat, EtatEnvoi.enAttente);
      client.refus = null;
      await d.actualiser();
      expect(d.messages.single.etat, EtatEnvoi.envoye);
      d.dispose();
    });
  });

  test('le suivi ne recharge rien tant qu’aucun message n’arrive', () async {
    client.fil.add(_json('m1', 'autre', 'Bonjour'));
    final d = discussion();
    await d.demarrer();
    await d.actualiser();
    expect(client.lectures304, 1);
    client.fil.add(_json('m2', 'autre', 'Vous êtes là ?'));
    await d.actualiser();
    expect(d.messages.map((m) => m.id), ['m1', 'm2']);
    d.dispose();
  });

  group('traduction', () {
    test('seul un message de l’autre personne dans une autre langue se traduit', () async {
      final d = discussion();
      await d.demarrer();
      MessageDiscussion m(String auteur, String texte, String langue) =>
          MessageDiscussion(id: 'x', auteurId: auteur, texte: texte, photos: const [], langue: langue, date: DateTime(2026));
      expect(d.peutTraduire(m('autre', 'مرحبا', 'ar')), isTrue);
      expect(d.peutTraduire(m('moi', 'مرحبا', 'ar')), isFalse);
      expect(d.peutTraduire(m('autre', 'Bonjour', 'fr')), isFalse);
      expect(d.peutTraduire(m('autre', '', 'ar')), isFalse);
      d.dispose();
    });

    test('traduit à la demande et bascule vers l’original', () async {
      client.fil.add(_json('m1', 'autre', 'مرحبا', langue: 'ar'));
      final d = discussion();
      await d.demarrer();
      expect(traduction.appels, 0, reason: 'rien ne part sans demande');
      await d.traduire(d.messages.single);
      expect(d.traduction('m1').texte, '[ar→fr] مرحبا');
      expect(d.traduction('m1').afficherTraduction, isTrue);
      d.basculerTraduction('m1');
      expect(d.traduction('m1').afficherTraduction, isFalse);
      d.dispose();
    });

    test('un échec de traduction peut être relancé', () async {
      client.fil.add(_json('m1', 'autre', 'مرحبا', langue: 'ar'));
      traduction.enPanne = true;
      final d = discussion();
      await d.demarrer();
      await d.traduire(d.messages.single);
      expect(d.traduction('m1').etat, EtatTraduction.erreur);
      traduction.enPanne = false;
      await d.traduire(d.messages.single);
      expect(d.traduction('m1').etat, EtatTraduction.traduit);
      d.dispose();
    });
  });

  test('aperçu de la dernière conversation', () {
    ConversationResume c(String texte, int photos, String auteur) => ConversationResume(
      id: 'c',
      annonceId: 'a',
      annonceTitre: 'Studio',
      interlocuteurNom: 'Sami',
      estProprietaire: false,
      nonLus: 0,
      date: DateTime(2026),
      dernierTexte: texte,
      dernierNbPhotos: photos,
      dernierAuteurId: auteur,
    );
    expect(c('Bonjour', 0, 'moi').apercu('moi'), 'Vous : Bonjour');
    expect(c('Bonjour', 0, 'sami').apercu('moi'), 'Bonjour');
    expect(c('', 3, 'sami').apercu('moi'), '3 photos');
    expect(c('', 1, 'moi').apercu('moi'), 'Vous : Photo');
  });

  group('écran', () {
    final conversation = ConversationResume(
      id: 'c1',
      annonceId: 'a',
      annonceTitre: 'Studio Manar',
      interlocuteurNom: 'Sami Ben Ali',
      estProprietaire: false,
      nonLus: 0,
      date: DateTime(2026),
    );

    Widget ecran(MessagerieService s) => MaterialApp(
      home: DiscussionScreen(
        conversation: conversation,
        userId: 'moi',
        langue: 'fr',
        service: s,
        traduction: traduction,
        periode: Duration.zero,
      ),
    );

    testWidgets('affiche la discussion et propose la traduction', (tester) async {
      await tester.pumpWidget(ecran(_ServiceMemoire([
        MessageDiscussion(id: 'm1', auteurId: 'autre', texte: 'مرحبا', photos: const [], langue: 'ar', date: DateTime(2026)),
        MessageDiscussion(id: 'm2', auteurId: 'moi', texte: 'Bonjour', photos: const [], langue: 'fr', date: DateTime(2026)),
      ])));
      await tester.pumpAndSettle();
      expect(find.text('Sami Ben Ali'), findsOneWidget);
      expect(find.text('Studio Manar'), findsOneWidget);
      expect(find.text('Traduire en français'), findsOneWidget);
      await tester.tap(find.text('Traduire en français'));
      await tester.pumpAndSettle();
      expect(find.text('[ar→fr] مرحبا'), findsOneWidget);
      expect(find.text('Traduction automatique, le texte original fait foi'), findsOneWidget);
    });

    testWidgets('envoyer vide la saisie et affiche le message', (tester) async {
      await tester.pumpWidget(ecran(_ServiceMemoire([])));
      await tester.pumpAndSettle();
      expect(find.text('Écrivez votre premier message.'), findsOneWidget);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Disponible en septembre ?');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(find.text('Disponible en septembre ?'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });
  });
}

/// Service sans base ni réseau, pour les tests d'écran.
class _ServiceMemoire extends MessagerieService {
  _ServiceMemoire(this._fil);
  final List<MessageDiscussion> _fil;

  @override
  Future<PageMessages> messages(String conversationId) async => PageMessages(List.of(_fil), null);

  @override
  Future<PageMessages?> nouveautes(String conversationId, {String? etag}) async => PageMessages(List.of(_fil), 'e');

  @override
  Future<List<MessageDiscussion>> enAttente(String userId, String conversationId) async => const [];

  @override
  Future<void> envoyerFile(String userId, {String? conversationId}) async {}

  @override
  Future<void> mettreEnFile({
    required String userId,
    required String conversationId,
    required String texte,
    required List<String> photos,
    required String langue,
  }) async {
    _fil.add(MessageDiscussion(id: 'n${_fil.length}', auteurId: userId, texte: texte, photos: photos, langue: langue, date: DateTime(2026)));
  }
}
