import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:studenthub/models/demande_maintenance.dart';
import 'package:studenthub/models/logement_loue.dart';
import 'package:studenthub/models/user_model.dart';
import 'package:studenthub/providers/demande_provider.dart';
import 'package:studenthub/providers/user_provider.dart';
import 'package:studenthub/screens/maintenance/demande_form_screen.dart';
import 'package:studenthub/services/demande_service.dart';
import 'package:studenthub/services/logement_loue_service.dart';
import 'package:studenthub/services/user_service.dart';

const _studioA = LogementLoue(
  annonceId: 'a',
  titre: 'Studio A',
  adresse: 'Tunis',
  proprietaireId: 'p1',
  proprietaireNom: 'Sami Ben Salah',
  debut: '2026-01-01',
  fin: '2099-12-31',
);
const _studioB = LogementLoue(
  annonceId: 'b',
  titre: 'Studio B',
  adresse: 'Sousse',
  proprietaireId: 'p2',
  proprietaireNom: 'Leila Trabelsi',
  debut: '2026-01-01',
  fin: '2099-12-31',
);

class _Utilisateurs extends UserService {
  _Utilisateurs(this.telephone);
  final String telephone;

  @override
  Future<UserModel?> getById(String userId) async => UserModel(
    id: userId,
    nom: 'Mansouri',
    prenom: 'Omar',
    email: 'omar@test.local',
    telephone: telephone,
    rolePrincipal: UserRole.locataire,
  );
}

class _Demandes extends DemandeService {
  @override
  Future<UserRole> roleDe(String acteurId) async => UserRole.locataire;

  @override
  Future<List<DemandeMaintenance>> lister(String acteurId) async => const [];
}

class _Logements extends LogementLoueService {
  _Logements(this.logements);
  final List<LogementLoue> logements;

  @override
  Future<void> synchroniser(String userId) async {}

  @override
  Future<List<LogementLoue>> lister(String userId) async => logements;
}

Future<void> _ouvrir(
  WidgetTester tester, {
  required List<LogementLoue> logements,
  String telephone = '+216 55 999 000',
  DemandeMaintenance? demande,
}) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final demandes = DemandeProvider(
    service: _Demandes(),
    logements: _Logements(logements),
  );
  final utilisateurs = UserProvider(service: _Utilisateurs(telephone));
  demandes.definirUtilisateur('u1');
  await tester.pump();
  await demandes.charger();
  await demandes.chargerLogements();
  await utilisateurs.load('u1');
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: demandes),
        ChangeNotifierProvider.value(value: utilisateurs),
      ],
      child: MaterialApp(home: DemandeFormScreen(demande: demande)),
    ),
  );
  await tester.pumpAndSettle();
}

String _texte(WidgetTester tester, String label) => tester
    .widget<TextFormField>(find.widgetWithText(TextFormField, label))
    .controller!
    .text;

void main() {
  testWidgets('reprend le nom du client et affiche le propriétaire', (
    tester,
  ) async {
    await _ouvrir(tester, logements: const [_studioA]);
    expect(find.text('Studio A'), findsOneWidget);
    expect(find.text('Propriétaire'), findsOneWidget);
    expect(find.text('Sami Ben Salah'), findsOneWidget);
    expect(_texte(tester, 'Nom du résident'), 'Omar Mansouri');
    expect(_texte(tester, 'Téléphone'), '55999000');
  });

  testWidgets('le propriétaire suit le logement choisi', (tester) async {
    await _ouvrir(tester, logements: const [_studioA, _studioB]);
    expect(find.text('Propriétaire'), findsNothing);

    await tester.tap(find.text('Logement concerné'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Studio B').last);
    await tester.pumpAndSettle();
    expect(find.text('Leila Trabelsi'), findsOneWidget);

    await tester.tap(find.text('Studio B').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Studio A').last);
    await tester.pumpAndSettle();
    expect(find.text('Sami Ben Salah'), findsOneWidget);
    expect(find.text('Leila Trabelsi'), findsNothing);
  });

  testWidgets('un numéro non tunisien n’est pas pré-rempli', (tester) async {
    await _ouvrir(
      tester,
      logements: const [_studioA],
      telephone: '+33 6 12 34 56 78',
    );
    expect(_texte(tester, 'Nom du résident'), 'Omar Mansouri');
    expect(_texte(tester, 'Téléphone'), isEmpty);
  });

  testWidgets('en modification, les valeurs de la demande sont conservées', (
    tester,
  ) async {
    await _ouvrir(
      tester,
      logements: const [],
      demande: DemandeMaintenance(
        id: 'd1',
        userId: 'u1',
        logementId: 'ancien',
        logementTitre: 'Ancien studio',
        proprietaireNom: 'Ancien propriétaire',
        category: 'plomberie',
        room: 'cuisine',
        urgency: 'moyenne',
        title: 'Fuite cuisine',
        description: 'Une description assez longue',
        residentName: 'Autre Nom',
        residentPhone: '12345678',
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    expect(find.text('Ancien studio'), findsOneWidget);
    expect(find.text('Ancien propriétaire'), findsOneWidget);
    expect(_texte(tester, 'Nom du résident'), 'Autre Nom');
    expect(_texte(tester, 'Téléphone'), '12345678');
  });
}
