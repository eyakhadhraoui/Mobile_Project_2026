import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:studenthub/models/complaint_model.dart';
import 'package:studenthub/models/conversation_reclamation.dart';
import 'package:studenthub/providers/assistant_reclamation_provider.dart';
import 'package:studenthub/screens/complaints/assistant_reclamation_screen.dart';
import 'package:studenthub/services/api_client.dart';
import 'package:studenthub/services/assistant_reclamation_service.dart';

Map<String, dynamic> _json({
  String id = 'c1',
  String texte = 'Prenez des photos de la fuite.',
  bool avis = false,
  List<String> questions = const [],
}) => {
  'id': id,
  'role': 'locataire',
  'titre': 'Fuite cuisine',
  'categorie': 'plomberie',
  'urgence': 'eleve',
  'statut': 'ouverte',
  'updatedAt': '2026-11-09T10:00:00.000Z',
  'messages': [
    {'auteur': 'utilisateur', 'texte': 'Une fuite dans ma cuisine', 'date': '2026-11-09T10:00:00.000Z'},
    {
      'auteur': 'assistant',
      'texte': texte,
      'date': '2026-11-09T10:00:00.000Z',
      'analyse': {
        'categorie': 'plomberie',
        'urgence': 'eleve',
        'personneConcernee': 'proprietaire',
        'informations': [
          {'champ': 'Lieu', 'valeur': 'Cuisine'},
        ],
        'questions': questions,
        'avisProfessionnel': avis,
      },
      'sources': [
        {'id': 'g', 'titre': 'Fuite d’eau et plomberie'},
      ],
    },
  ],
};

class _Service extends AssistantReclamationService {
  String role = 'locataire';
  String texteReponse = 'Prenez des photos de la fuite.';
  List<ConversationReclamation> historique = const [];
  ApiException? erreur;
  final envois = <String>[];
  final statuts = <String>[];
  final supprimes = <String>[];

  @override
  Future<({String role, List<ConversationReclamation> conversations})> lister() async {
    if (erreur case final e?) throw e;
    return (role: role, conversations: historique);
  }

  @override
  Future<ConversationReclamation> detail(String id) async => ConversationReclamation.fromJson(_json(id: id));

  @override
  Future<ConversationReclamation> creer(String message) async {
    if (erreur case final e?) throw e;
    envois.add('creer:$message');
    return ConversationReclamation.fromJson(_json(texte: texteReponse));
  }

  @override
  Future<ConversationReclamation> envoyer(String id, String message) async {
    if (erreur case final e?) throw e;
    envois.add('$id:$message');
    return ConversationReclamation.fromJson(_json(id: id));
  }

  @override
  Future<ConversationReclamation> changerStatut(String id, String statut) async {
    statuts.add(statut);
    return ConversationReclamation.fromJson({..._json(id: id), 'statut': statut});
  }

  @override
  Future<void> supprimer(String id) async => supprimes.add(id);
}

const _reseau = ApiException('x', code: 'network');

Future<void> _discussion(WidgetTester tester, AssistantReclamationProvider provider) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: ConversationReclamationScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  test('le format du serveur est lu, avec des valeurs par défaut', () {
    final c = ConversationReclamation.fromJson(_json(avis: true, questions: const ['Depuis quand ?']));
    expect(c.messages.first.deUtilisateur, isTrue);
    final analyse = c.messages.last.analyse!;
    expect(analyse.personneConcernee, 'proprietaire');
    expect(analyse.informations.single.valeur, 'Cuisine');
    expect(analyse.questions.single, 'Depuis quand ?');
    expect(analyse.avisProfessionnel, isTrue);
    expect(c.messages.last.sources.single, contains('Fuite'));
    expect(ConversationReclamation.fromJson({'id': 'x'}).categorie, 'autre');
  });

  test('estTexteArabe', () {
    expect(estTexteArabe('يوجد تسرب ماء'), isTrue);
    expect(estTexteArabe('Il y a une fuite'), isFalse);
    expect(estTexteArabe(''), isFalse);
  });

  test('les catégories de l’IA correspondent à celles du formulaire', () {
    expect(categorieFormulaire('plomberie'), ComplaintCategory.fuiteEau);
    expect(categorieFormulaire('retard_loyer'), ComplaintCategory.autre);
    expect(categorieFormulaire('contrat'), ComplaintCategory.proprietaire);
  });

  group('provider', () {
    test('une nouvelle réclamation crée la conversation, le message suivant la complète', () async {
      final service = _Service();
      final provider = AssistantReclamationProvider(service: service);
      expect(await provider.envoyer('Fuite'), isTrue);
      expect(provider.courante!.id, 'c1');
      expect(provider.conversations.single.id, 'c1');
      await provider.envoyer('Depuis hier');
      expect(service.envois, ['creer:Fuite', 'c1:Depuis hier']);
      expect(provider.conversations, hasLength(1));
    });

    test('sans connexion, l’échec est expliqué et rien n’est perdu', () async {
      final service = _Service()..erreur = _reseau;
      final provider = AssistantReclamationProvider(service: service);
      expect(await provider.envoyer('Fuite'), isFalse);
      expect(provider.erreur, contains('connexion'));
      expect(provider.envoiEnCours, isFalse);
      expect(provider.courante, isNull);
    });

    test('statut et suppression', () async {
      final service = _Service();
      final provider = AssistantReclamationProvider(service: service);
      await provider.envoyer('Fuite');
      await provider.changerStatut('resolue');
      expect(provider.courante!.statut, 'resolue');
      expect(await provider.supprimer('c1'), isTrue);
      expect(provider.courante, isNull);
      expect(provider.conversations, isEmpty);
    });

    test('un prestataire n’est pas accepté', () async {
      final provider = AssistantReclamationProvider(service: _Service()..role = 'prestataire');
      await provider.charger();
      expect(provider.roleAccepte, isFalse);
    });
  });

  group('écrans', () {
    testWidgets('la réponse affiche badges, questions, avis professionnel et sources', (tester) async {
      final service = _Service();
      final provider = AssistantReclamationProvider(service: service);
      await _discussion(tester, provider);
      expect(find.text('Locataire'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Une fuite dans ma cuisine');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();
      await tester.pump();
      expect(service.envois.single, 'creer:Une fuite dans ma cuisine');
      expect(find.text('Prenez des photos de la fuite.'), findsOneWidget);
      expect(find.text('Urgence élevée'), findsOneWidget);
      expect(find.text('Plomberie et fuite d’eau'), findsOneWidget);
      expect(find.text('Concerne : Le propriétaire'), findsNothing);
      await tester.tap(find.text('Détails de l’analyse'));
      await tester.pumpAndSettle();
      expect(find.text('Concerne : Le propriétaire'), findsOneWidget);
      expect(find.text('Lieu : Cuisine'), findsOneWidget);
      expect(find.textContaining('Sources :'), findsOneWidget);
      expect(find.text('Créer la réclamation officielle'), findsOneWidget);
    });

    testWidgets('une suggestion remplit la zone de saisie selon le rôle', (tester) async {
      final provider = AssistantReclamationProvider(service: _Service());
      await _discussion(tester, provider);
      await tester.tap(find.text('Caution non rendue'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, contains('caution'));
    });

    testWidgets('après un échec, le texte revient dans la zone de saisie', (tester) async {
      final provider = AssistantReclamationProvider(service: _Service()..erreur = _reseau);
      await _discussion(tester, provider);
      await tester.enterText(find.byType(TextField), 'Une fuite');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Une fuite');
      expect(find.textContaining('connexion'), findsOneWidget);
    });

    testWidgets('une réponse en arabe se lit de droite à gauche', (tester) async {
      const arabe = 'يرجى التقاط صور للتسرب';
      final service = _Service()..texteReponse = arabe;
      final provider = AssistantReclamationProvider(service: service);
      await provider.envoyer('x');
      await _discussion(tester, provider);
      expect(tester.widget<Text>(find.text(arabe)).textDirection, TextDirection.rtl);
      expect(
        tester.widget<Text>(find.text('Une fuite dans ma cuisine')).textDirection,
        TextDirection.ltr,
      );
    });

    testWidgets('l’historique liste les conversations et mène à la discussion', (tester) async {
      final service = _Service()
        ..historique = [ConversationReclamation.fromJson({..._json(), 'messages': const []})];
      await tester.pumpWidget(MaterialApp(home: AssistantReclamationsScreen(service: service)));
      await tester.pumpAndSettle();
      expect(find.text('Fuite cuisine'), findsOneWidget);
      expect(find.text('Urgence élevée'), findsOneWidget);
      expect(find.text('Ouverte'), findsOneWidget);
      await tester.tap(find.text('Fuite cuisine'));
      await tester.pumpAndSettle();
      expect(find.text('Prenez des photos de la fuite.'), findsOneWidget);
    });

    testWidgets('l’accès est fermé aux autres rôles', (tester) async {
      await tester.pumpWidget(MaterialApp(home: AssistantReclamationsScreen(service: _Service()..role = 'prestataire')));
      await tester.pumpAndSettle();
      expect(find.textContaining('réservé aux locataires'), findsOneWidget);
      expect(find.text('Nouvelle réclamation'), findsNothing);
    });
  });
}
