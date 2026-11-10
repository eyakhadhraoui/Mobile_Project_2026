import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:studenthub/core/theme/app_theme.dart';
import 'package:studenthub/models/annonce.dart';
import 'package:studenthub/models/messagerie.dart';
import 'package:studenthub/providers/messagerie_provider.dart';
import 'package:studenthub/services/messagerie_service.dart';
import 'package:studenthub/providers/annonce_provider.dart';
import 'package:studenthub/providers/auth_provider.dart';
import 'package:studenthub/providers/trajet_provider.dart';
import 'package:studenthub/providers/user_provider.dart';
import 'package:studenthub/screens/announcements/announcements_screen.dart';
import 'package:studenthub/services/annonce_cache_service.dart';
import 'package:studenthub/services/annonce_service.dart';
import 'package:studenthub/services/auth_service.dart';
import 'package:studenthub/services/heure_service.dart';

Annonce _annonce(String id, String titre, String proprietaire, String nom) =>
    Annonce.fromJson({
      'id': id,
      'categorie': 'Autre',
      'titre': titre,
      'description': 'Bureau en bois, très bon état.',
      'photos': <String>[],
      'statut': 'publiee',
      'motifModeration': '',
      'proprietaireId': proprietaire,
      'proprietaireNom': nom,
      'autoriserCommentaires': true,
      'createdAt': '2026-11-05T10:00:00.000Z',
      'likes': 3,
      'aimeParMoi': false,
      'nbCommentaires': 2,
      'noteMoyenne': 0,
      'nbAvis': 0,
      'maNote': null,
    });

class _Serveur extends AnnonceService {
  List<Annonce> items = [
    _annonce('a_moi', 'Mon annonce', 'me', 'Moi'),
    _annonce('a_autre', 'Annonce d’un autre', 'autre', 'Omar Mansouri'),
  ];
  final supprimees = <String>[];

  @override
  Future<int> migrerAnnoncesLocales(String userId) async => 0;

  @override
  Future<AnnoncesPage?> lister({String? etag}) async =>
      AnnoncesPage(annonces: items, meId: 'me', meRole: 'etudiant', etag: 'v1');

  @override
  Future<void> supprimer(String id) async => supprimees.add(id);
}

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
  Future<void> supprimer(String id) async {}
  @override
  Future<void> vider() async {}
}

class _Auth extends AuthService {
  @override
  Stream<String?> get authStateChanges => Stream<String?>.value('me');
  @override
  Future<String?> getCurrentUserId() async => 'me';
}

Future<void> _afficher(WidgetTester tester, _Serveur serveur) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final annonces = AnnonceProvider(
    service: serveur,
    cache: _CacheMemoire(),
    intervalle: const Duration(hours: 1),
    intervallePlanificateur: const Duration(hours: 1),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(service: _Auth())),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => MessagerieProvider(service: _Messagerie())),
        ChangeNotifierProvider(create: (_) => TrajetProvider()),
        // Libéré au démontage de l'arbre, ce qui arrête ses minuteurs.
        ChangeNotifierProvider(create: (_) => annonces),
        Provider(create: (_) => HeureService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SafeArea(child: AnnouncementsScreen())),
      ),
    ),
  );
  annonces.utilisateur('me');
  await tester.pumpAndSettle();
}

Future<void> _fin(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

class _Messagerie extends MessagerieService {
  @override
  Future<void> envoyerFile(String userId, {String? conversationId}) async {}

  @override
  Future<List<ConversationResume>> conversations() async => const [];
}

void main() {
  testWidgets('seul le propriétaire voit Modifier et Supprimer sur la carte', (
    tester,
  ) async {
    await _afficher(tester, _Serveur());
    expect(find.text('Mon annonce'), findsOneWidget);
    expect(find.text('Annonce d’un autre'), findsOneWidget);
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);
    await _fin(tester);
  });

  testWidgets('Supprimer demande confirmation puis retire l’annonce', (
    tester,
  ) async {
    final serveur = _Serveur();
    await _afficher(tester, serveur);

    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer cette annonce ?'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(serveur.supprimees, isEmpty);
    expect(find.text('Mon annonce'), findsOneWidget);

    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(serveur.supprimees, ['a_moi']);
    expect(find.text('Mon annonce'), findsNothing);
    expect(find.text('Annonce supprimée.'), findsOneWidget);
    expect(find.text('Annonce d’un autre'), findsOneWidget);
    await _fin(tester);
  });

  testWidgets('Modifier ouvre le formulaire de l’annonce', (tester) async {
    await _afficher(tester, _Serveur());
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier l’annonce'), findsOneWidget);
    await _fin(tester);
  });
}
