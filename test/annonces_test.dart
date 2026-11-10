import 'package:flutter_test/flutter_test.dart';
import 'package:studenthub/models/annonce.dart';
import 'package:studenthub/providers/annonce_provider.dart';
import 'package:studenthub/services/annonce_cache_service.dart';
import 'package:studenthub/services/annonce_file_service.dart';
import 'package:studenthub/services/annonce_service.dart';
import 'package:studenthub/services/api_client.dart';

/// Annonce telle que renvoyée par GET /annonces.
Map<String, dynamic> _json({String id = 'a1', bool aime = false, int likes = 0}) => {
  'id': id,
  'categorie': 'Logement',
  'titre': 'Studio près de la fac',
  'description': 'Calme',
  'typeLocation': 'Studio',
  'loyer': 450,
  'surface': 22,
  'chambres': 1,
  'etage': null,
  'ville': 'Tunis',
  'quartier': '',
  'adresse': '12 rue X',
  'photos': ['/photos/0123456789abcdef0123456789abcdef.jpg'],
  'statut': 'enAttente',
  'motifModeration': '',
  'proprietaireId': 'owner',
  'proprietaireNom': 'Sami Ben',
  'autoriserCommentaires': true,
  'createdAt': '2026-11-05T10:00:00.000Z',
  'likes': likes,
  'aimeParMoi': aime,
  'nbCommentaires': 2,
  'noteMoyenne': 4.5,
  'nbAvis': 2,
  'maNote': null,
};

class _FakeService extends AnnonceService {
  int listCalls = 0;
  String? lastEtag;
  bool failLike = false;
  List<Annonce> items = [Annonce.fromJson(_json())];

  @override
  Future<int> migrerAnnoncesLocales(String userId) async => 0;

  @override
  Future<AnnoncesPage?> lister({String? etag}) async {
    listCalls++;
    lastEtag = etag;
    if (etag == 'v1') return null; // 304 : rien de changé
    return AnnoncesPage(annonces: items, meId: 'me', meRole: 'administrateur', etag: 'v1');
  }

  @override
  Future<void> aimer(String id, bool aime) async {
    if (failLike) throw const ApiException('Refusé', status: 409);
  }
}

/// Cache hors ligne sans base de données (ces tests ne portent pas sur SQLite).
class _CacheMemoire extends AnnonceCacheService {
  @override
  Future<void> remplacer(String userId, List<Annonce> annonces) async {}
  @override
  Future<void> enregistrer(String userId, Annonce annonce) async {}
  @override
  Future<List<Annonce>> lire(String userId) async => const [];
  @override
  Future<bool> aDesProgrammees(String userId) async => false;
  @override
  Future<void> vider() async {}
}

/// File d'envoi sans base de données.
class _FileMemoire extends AnnonceFileService {
  @override
  Future<List<OperationAnnonce>> lister(String userId) async => const [];
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('Annonce lit le format serveur et n’envoie les champs logement que pour un logement', () {
    final annonce = Annonce.fromJson(_json());
    expect(annonce.estLogement, isTrue);
    expect(annonce.loyer, 450);
    expect(annonce.etage, isNull);
    expect(annonce.statut, StatutAnnonce.enAttente);
    expect(annonce.noteMoyenne, 4.5);
    expect(annonce.toPayload()['loyer'], 450);

    final avis = annonce.copyWith(categorie: 'Avis');
    expect(avis.toPayload().containsKey('loyer'), isFalse);
    expect(avis.toPayload()['photos'], annonce.photos);
  });

  test('ApiClient reconnaît les photos serveur', () {
    expect(ApiClient.isRemotePhoto('/photos/abc.jpg'), isTrue);
    expect(ApiClient.isRemotePhoto('/data/user/0/cache/img.jpg'), isFalse);
  });

  test('Provider : chargement, ETag 304, like optimiste annulé en cas d’échec', () async {
    final service = _FakeService();
    final provider = AnnonceProvider(service: service, cache: _CacheMemoire(), file: _FileMemoire(), intervalle: const Duration(hours: 1));
    provider.utilisateur('me');
    await _settle();
    await _settle();
    expect(provider.annonces, hasLength(1));
    expect(provider.estAdmin, isTrue);
    expect(provider.aModerer, 1);

    // Rafraîchissement silencieux avec l'ETag : 304, la liste reste en place.
    await provider.charger(silencieux: true);
    expect(service.lastEtag, 'v1');
    expect(provider.annonces, hasLength(1));

    service.failLike = true;
    final annonce = provider.annonces.first;
    await expectLater(provider.basculerLike(annonce), throwsA(isA<ApiException>()));
    expect(provider.annonces.first.aimeParMoi, isFalse);
    expect(provider.annonces.first.likes, 0);

    service.failLike = false;
    await provider.basculerLike(provider.annonces.first);
    expect(provider.annonces.first.aimeParMoi, isTrue);
    expect(provider.annonces.first.likes, 1);

    // Déconnexion : la liste est vidée.
    provider.utilisateur(null);
    expect(provider.annonces, isEmpty);
    await _settle();
    provider.dispose();
    await _settle(); // aucune notification après dispose
  });
}
