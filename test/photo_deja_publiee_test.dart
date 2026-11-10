import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studenthub/models/annonce.dart';
import 'package:studenthub/models/conversation_reclamation.dart';
import 'package:studenthub/screens/announcements/photo_deja_publiee.dart';
import 'package:studenthub/screens/complaints/assistant_reclamation_screen.dart';
import 'package:studenthub/services/annonce_service.dart';
import 'package:studenthub/services/api_client.dart';
import 'package:studenthub/services/assistant_reclamation_service.dart';

class _Api extends ApiClient {
  Object? reponse;
  ApiException? erreur;
  final appels = <String>[];
  List<int>? octets;

  @override
  Future<ApiResponse> send(String method, String path, {Object? body, String? etag, bool authenticated = true, List<int>? bytes}) async {
    appels.add('$method $path');
    octets = bytes;
    if (erreur case final e?) throw e;
    return ApiResponse(200, reponse, null);
  }
}

class _Assistant extends AssistantReclamationService {
  final envoyes = <String>[];
  bool enPanne = false;

  @override
  Future<({String role, List<ConversationReclamation> conversations})> lister() async => (role: 'locataire', conversations: const <ConversationReclamation>[]);

  @override
  Future<ConversationReclamation> creer(String message) async {
    if (enPanne) throw const ApiException('Serveur injoignable', code: 'network');
    envoyes.add(message);
    throw const ApiException('fin du test', status: 500);
  }
}

void main() {
  group('vérification d’une photo', () {
    late Directory dossier;
    late File photo;
    late _Api api;
    late AnnonceService service;

    setUp(() {
      dossier = Directory.systemTemp.createTempSync('photo_');
      photo = File('${dossier.path}/p.jpg')..writeAsBytesSync([1, 2, 3]);
      api = _Api();
      service = AnnonceService(api: api);
    });

    tearDown(() => dossier.deleteSync(recursive: true));

    test('envoie l’image et lit la correspondance', () async {
      api.reponse = {
        'correspondance': {'niveau': 'confirmee_ia', 'photoCible': '/photos/y.jpg', 'annonceCibleTitre': 'Studio'},
      };
      final trouvee = await service.verifierPhoto(photo.path);
      expect(api.appels, ['POST /photos/verifier']);
      expect(api.octets, [1, 2, 3]);
      expect(trouvee!.niveau, 'confirmee_ia');
      expect(trouvee.annonceCibleTitre, 'Studio');
    });

    test('aucune correspondance', () async {
      api.reponse = {'correspondance': null};
      expect(await service.verifierPhoto(photo.path), isNull);
    });

    test('sans réseau ni fichier, le formulaire reste utilisable', () async {
      api.erreur = const ApiException('Serveur injoignable', code: 'network');
      expect(await service.verifierPhoto(photo.path), isNull);
      api.erreur = null;
      expect(await service.verifierPhoto('${dossier.path}/absent.jpg'), isNull);
    });
  });

  test('la réclamation cite l’annonce quand elle est connue', () {
    expect(messageReclamationPhoto('Studio Manar'), contains('« Studio Manar »'));
    expect(messageReclamationPhoto(null), contains('une autre annonce'));
  });

  testWidgets('« Changer la photo » revient simplement au formulaire', (tester) async {
    late BuildContext contexte;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        contexte = context;
        return const Scaffold();
      }),
    ));
    afficherAlertePhoto(contexte, photoLocale: '/introuvable.jpg', correspondance: const CorrespondancePhoto(niveau: 'certaine'));
    await tester.pumpAndSettle();
    expect(find.textContaining('changez-la'), findsOneWidget);
    expect(find.textContaining('envoyez une réclamation à notre chatbot'), findsOneWidget);
    await tester.tap(find.text('Changer la photo'));
    await tester.pumpAndSettle();
    expect(find.text('Photo déjà publiée'), findsNothing);
    expect(find.byType(ReclamationPhotoScreen), findsNothing);
  });

  testWidgets('sans vignette quand le serveur a refusé à la publication', (tester) async {
    late BuildContext contexte;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        contexte = context;
        return const Scaffold();
      }),
    ));
    afficherAlertePhoto(contexte);
    await tester.pumpAndSettle();
    expect(find.text('Votre photo'), findsNothing);
    expect(find.text('C’est ma maison'), findsOneWidget);
  });

  testWidgets('la réclamation part toute seule au chatbot', (tester) async {
    final assistant = _Assistant();
    await tester.pumpWidget(MaterialApp(home: ReclamationPhotoScreen(message: 'Ma réclamation', service: assistant)));
    await tester.pumpAndSettle();
    expect(assistant.envoyes, ['Ma réclamation']);
  });

  testWidgets('si l’envoi échoue, le texte reste à renvoyer', (tester) async {
    final assistant = _Assistant()..enPanne = true;
    await tester.pumpWidget(MaterialApp(home: ReclamationPhotoScreen(message: 'Ma réclamation', service: assistant)));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Ma réclamation');
  });
}
