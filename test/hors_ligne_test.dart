import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studenthub/models/annonce.dart';
import 'package:studenthub/providers/annonce_provider.dart';
import 'package:studenthub/services/annonce_cache_service.dart';
import 'package:studenthub/services/annonce_file_service.dart';
import 'package:studenthub/services/annonce_service.dart';
import 'package:studenthub/services/api_client.dart';
import 'package:studenthub/services/app_database.dart';
import 'package:studenthub/services/database_helper.dart';
import 'package:studenthub/services/photo_storage.dart';

const _reseau = ApiException('Serveur injoignable', code: 'network');

/// Serveur simulé : hors ligne tant que [enPanne] est vrai.
class _Serveur extends AnnonceService {
  bool enPanne = true;
  ApiException? refus;
  List<Annonce> enLigne = const [];
  final appels = <String>[];
  final creees = <Annonce>[];

  void _verifier(String appel) {
    if (enPanne) throw _reseau;
    if (refus case final erreur?) throw erreur;
    appels.add(appel);
  }

  @override
  Future<int> migrerAnnoncesLocales(String userId) async => 0;

  @override
  Future<AnnoncesPage?> lister({String? etag}) async {
    if (enPanne) throw _reseau;
    return AnnoncesPage(annonces: enLigne, meId: 'moi', meRole: 'locataire');
  }

  @override
  Future<Annonce> ajouter(Annonce annonce) async {
    _verifier('ajouter');
    return annonce;
  }

  @override
  Future<Annonce> ajouterDepuisFile(Annonce annonce) async {
    _verifier('ajouterDepuisFile:${annonce.titre}');
    creees.add(annonce);
    return annonce;
  }

  @override
  Future<Annonce> modifier(Annonce annonce) async {
    _verifier('modifier:${annonce.titre}');
    return annonce;
  }

  @override
  Future<void> supprimer(String id) async => _verifier('supprimer:$id');

  @override
  Future<void> aimer(String id, bool aime) async => _verifier('aimer:$id:$aime');

  @override
  Future<Annonce> noter(String id, int note) async {
    _verifier('noter:$id:$note');
    return enLigne.first;
  }

  @override
  Future<List<CommentaireAnnonce>> commentaires(String id) async {
    if (enPanne) throw _reseau;
    return const [];
  }

  @override
  Future<List<CommentaireAnnonce>> commenter(String id, String texte) async {
    _verifier('commenter:$id:$texte');
    return const [];
  }
}

Annonce _annonce({String id = '', String titre = 'Studio', List<String> photos = const [], DateTime? date}) => Annonce(
  id: id,
  categorie: 'Avis',
  titre: titre,
  description: 'd',
  photos: photos,
  proprietaireId: 'moi',
  datePublication: date,
);

Annonce _serveur(String id, {bool aime = false, int likes = 2}) => Annonce.fromJson({
  'id': id,
  'categorie': 'Avis',
  'titre': 'En ligne',
  'description': 'd',
  'statut': 'publiee',
  'proprietaireId': 'autre',
  'likes': likes,
  'aimeParMoi': aime,
  'nbCommentaires': 1,
});

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dossier;
  late DatabaseHelper base;
  late _Serveur serveur;
  late AnnonceCacheService cache;
  late PhotoStorage photos;
  final ouverts = <AnnonceProvider>[];

  Future<AnnonceProvider> ouvrir([String utilisateur = 'moi']) async {
    final provider = AnnonceProvider(
      service: serveur,
      cache: cache,
      file: AnnonceFileService(databaseHelper: base),
      photos: photos,
      intervalle: const Duration(hours: 1),
      intervallePlanificateur: const Duration(hours: 1),
    );
    ouverts.add(provider);
    provider.utilisateur(utilisateur);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return provider;
  }

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('hors_ligne');
    base = DatabaseHelper.forTests(path: p.join(dossier.path, 'studenthub.db'));
    serveur = _Serveur();
    cache = AnnonceCacheService(databaseHelper: base);
    photos = PhotoStorage(documentsDirectory: () async => dossier);
  });

  tearDown(() async {
    for (final provider in ouverts) {
      provider.dispose();
    }
    ouverts.clear();
    await (await base.database).close();
    await dossier.delete(recursive: true);
  });

  test('une annonce créée sans réseau survit au redémarrage puis part une seule fois', () async {
    var provider = await ouvrir();
    final locale = await provider.ajouter(_annonce());
    expect(locale.id, startsWith('local_'));
    expect(provider.estEnAttenteEnvoi(locale.id), isTrue);
    expect(provider.annonces.single.titre, 'Studio');

    provider.dispose();
    ouverts.clear();
    provider = await ouvrir();
    expect(provider.actionsEnAttente, 1);
    expect(provider.annonces.single.id, locale.id);

    serveur.enPanne = false;
    await provider.charger();
    await provider.charger();
    expect(serveur.appels, ['ajouterDepuisFile:Studio']);
    expect(serveur.creees.single.id, locale.id);
    expect(provider.actionsEnAttente, 0);
    expect(provider.horsLigne, isFalse);
  });

  test('une photo temporaire est conservée jusqu’à l’envoi puis effacée', () async {
    final temporaire = File(p.join(dossier.path, 'picker.jpg'))..writeAsBytesSync([1, 2, 3]);
    final provider = await ouvrir();
    final locale = await provider.ajouter(_annonce(photos: [temporaire.path]));
    temporaire.deleteSync();

    final copie = locale.photos.single;
    expect(copie, isNot(temporaire.path));
    expect(File(copie).existsSync(), isTrue);

    serveur.enPanne = false;
    await provider.charger();
    expect(File(copie).existsSync(), isFalse);
  });

  test('modifier une annonce encore en attente met à jour la création', () async {
    final provider = await ouvrir();
    final locale = await provider.ajouter(_annonce());
    await provider.modifier(_annonce(id: locale.id, titre: 'Studio corrigé'));
    expect(provider.actionsEnAttente, 1);
    expect(provider.annonces.single.titre, 'Studio corrigé');

    serveur.enPanne = false;
    await provider.charger();
    expect(serveur.appels, ['ajouterDepuisFile:Studio corrigé']);
  });

  test('supprimer une annonce jamais envoyée ne contacte pas le serveur', () async {
    final provider = await ouvrir();
    final locale = await provider.ajouter(_annonce());
    await provider.supprimer(locale.id);
    expect(provider.annonces, isEmpty);
    expect(provider.actionsEnAttente, 0);

    serveur.enPanne = false;
    await provider.charger();
    expect(serveur.appels, isEmpty);
  });

  test('like, note, commentaire et suppression attendent puis partent dans l’ordre', () async {
    serveur.enPanne = false;
    serveur.enLigne = [_serveur('a'), _serveur('b')];
    final provider = await ouvrir();
    await provider.charger();
    serveur.enPanne = true;

    await provider.basculerLike(provider.parId('a')!);
    expect(provider.parId('a')!.likes, 3);
    await provider.noter('a', 4);
    expect(provider.parId('a')!.maNote, 4);
    await provider.noter('a', 5);
    final commentaires = await provider.commenter('a', 'Bonjour');
    expect(commentaires.single.texte, 'Bonjour');
    expect(provider.parId('a')!.nbCommentaires, 2);
    await provider.supprimer('b');
    expect(provider.parId('b'), isNull);
    expect(provider.actionsEnAttente, 4);

    serveur.enPanne = false;
    await provider.charger();
    expect(serveur.appels, ['aimer:a:true', 'noter:a:5', 'commenter:a:Bonjour', 'supprimer:b']);
    expect(provider.actionsEnAttente, 0);
  });

  test('un refus du serveur abandonne l’action et le signale', () async {
    final provider = await ouvrir();
    await provider.ajouter(_annonce());
    serveur.enPanne = false;
    serveur.refus = const ApiException('Titre invalide', status: 400);
    await provider.charger();
    expect(provider.actionsEnAttente, 0);
    expect(provider.refusEnvoi, contains('Titre invalide'));
    provider.oublierRefusEnvoi();
    expect(provider.refusEnvoi, isNull);
  });

  test('une erreur passagère du serveur garde l’action en file', () async {
    final provider = await ouvrir();
    await provider.ajouter(_annonce());
    serveur.enPanne = false;
    serveur.refus = const ApiException('Erreur interne', status: 500);
    await expectLater(provider.charger(), throwsA(isA<ApiException>()));
    expect(provider.actionsEnAttente, 1);
    expect(provider.refusEnvoi, isNull);
  });

  test('une date programmée dépassée pendant la panne devient une publication immédiate', () async {
    final provider = await ouvrir();
    final date = DateTime.now().add(const Duration(milliseconds: 80));
    await provider.ajouter(_annonce(date: date));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    serveur.enPanne = false;
    await provider.charger();
    expect(serveur.creees.single.datePublication, isNull);
  });

  test('les annonces en cache restent lisibles après déconnexion, pour ce compte seulement', () async {
    serveur.enPanne = false;
    serveur.enLigne = [_serveur('a')];
    var provider = await ouvrir();
    await provider.charger();
    provider.utilisateur(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    provider.dispose();
    ouverts.clear();

    serveur.enPanne = true;
    provider = await ouvrir();
    expect(provider.annonces.single.id, 'a');
    provider.dispose();
    ouverts.clear();

    provider = await ouvrir('autre_compte');
    expect(provider.annonces, isEmpty);
  });

  group('ApiClient.getAvecCache', () {
    late _Api api;

    setUp(() async {
      api = _Api(_Db(base));
      final db = await base.database;
      await db.insert('app_settings', {'key': 'currentUserId', 'value': 'moi'});
    });

    test('rend la dernière réponse sans connexion', () async {
      api.reponse = {'recues': [1]};
      expect(await api.getAvecCache('/visites'), {'recues': [1]});
      api.erreur = _reseau;
      expect(await api.getAvecCache('/visites'), {'recues': [1]});
    });

    test('sans copie, l’erreur réseau remonte', () {
      api.erreur = _reseau;
      expect(api.getAvecCache('/activite'), throwsA(isA<ApiException>()));
    });

    test('un refus du serveur ne se cache pas derrière la copie', () async {
      api.reponse = {'a': 1};
      await api.getAvecCache('/visites');
      api.erreur = const ApiException('Interdit', status: 403);
      expect(api.getAvecCache('/visites'), throwsA(isA<ApiException>()));
    });
  });
}

class _Db implements AppDatabase {
  _Db(this.helper);
  final DatabaseHelper helper;
  @override
  Future<Database> get database => helper.database;
}

class _Api extends ApiClient {
  _Api(AppDatabase db) : super(database: db);
  Object? reponse;
  ApiException? erreur;

  @override
  Future<ApiResponse> send(
    String method,
    String path, {
    Object? body,
    String? etag,
    bool authenticated = true,
    List<int>? bytes,
  }) async {
    if (erreur case final e?) throw e;
    return ApiResponse(200, reponse, null);
  }
}
