import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studenthub/screens/announcements/estimation_prix_screen.dart';
import 'package:studenthub/services/estimation_prix_service.dart';

void main() {
  final service = EstimationPrixService.depuisJson(File('assets/modele_prix.json').readAsStringSync());

  double loyer({String ville = 'Tunis', String? quartier, double surface = 80, CategorieBien categorie = CategorieBien.appartement}) =>
      service.estimer(type: TypeTransaction.louer, categorie: categorie, ville: ville, quartier: quartier, surface: surface, chambres: 2, sdb: 1)!.prix;

  for (final type in TypeTransaction.values) {
    test('le calcul de l’application égale celui de l’entraînement (${type.name})', () {
      for (final exemple in service.controle(type)) {
        final log = service.logPrix(
          type: type,
          categorie: CategorieBien.values.byName(exemple['categorie'] as String),
          ville: exemple['ville'] as String,
          quartier: exemple['quartier'] as String,
          surface: (exemple['surface'] as num).toDouble(),
          chambres: (exemple['chambres'] as num?)?.toInt(),
          sdb: (exemple['sdb'] as num?)?.toInt(),
        )!;
        expect(log, closeTo(exemple['attendu'] as num, 0.02), reason: exemple.toString());
      }
    });
  }

  test('le prix augmente avec la surface', () {
    expect(loyer(surface: 120), greaterThan(loyer(surface: 60)));
  });

  test('l’emplacement compte : La Marsa plus cher que Kasserine', () {
    expect(loyer(quartier: 'La Marsa'), greaterThan(loyer(ville: 'Kasserine')));
  });

  test('un prix de vente est bien plus élevé qu’un loyer', () {
    final vente = service.estimer(type: TypeTransaction.vendre, categorie: CategorieBien.appartement, ville: 'Tunis', surface: 80, chambres: 2)!;
    expect(vente.prix, greaterThan(loyer() * 50));
  });

  test('la fourchette encadre le prix et les arrondis sont lisibles', () {
    final e = service.estimer(type: TypeTransaction.louer, categorie: CategorieBien.appartement, ville: 'Tunis', surface: 80)!;
    expect(e.bas, lessThan(e.prix));
    expect(e.haut, greaterThan(e.prix));
    expect(e.prix % 10, 0);
    expect(e.erreurMediane, inInclusiveRange(0.05, 0.6));
  });

  test('la colocation est signalée comme peu fiable, faute de données', () {
    final e = service.estimer(type: TypeTransaction.louer, categorie: CategorieBien.colocation, ville: 'Tunis', surface: 20)!;
    expect(e.confiance, ConfianceEstimation.faible);
  });

  test('un champ vide vaut la valeur courante pour la surface, pas zéro', () {
    double prix(int? c, int? s) => service.estimer(type: TypeTransaction.louer, categorie: CategorieBien.appartement, ville: 'Ariana', surface: 80, chambres: c, sdb: s)!.prix;
    expect(prix(null, null), prix(2, 1));
    expect(EstimationPrixService.chambresCourantes(50), 1);
    expect(EstimationPrixService.sdbCourantes(200), 2);
  });

  test('une ville inconnue ne produit pas de prix', () {
    expect(service.estimer(type: TypeTransaction.louer, categorie: CategorieBien.appartement, ville: 'Paris', surface: 80), isNull);
  });

  test('un quartier inconnu retombe sur la ville et le dit', () {
    final e = service.estimer(type: TypeTransaction.louer, categorie: CategorieBien.appartement, ville: 'Tunis', quartier: 'Nulle part', surface: 80)!;
    expect(e.quartierUtilise, isFalse);
  });

  group('resoudreLieu', () {
    ({String ville, String? quartier})? lieu(String v, String q) => service.resoudreLieu(TypeTransaction.louer, v, q);

    test('ville du gouvernorat', () => expect(lieu('Tunis', 'Rue inconnue')?.ville, 'Tunis'));
    test('préfixe gouvernorat et casse', () => expect(lieu('Gouvernorat de Sousse', '')?.ville, 'Sousse'));
    test('quartier retrouvé sans accent ni casse', () {
      final r = lieu('Tunis', 'la marsa');
      expect(r?.quartier, 'La Marsa');
    });
    test('une commune donnée comme ville retrouve son gouvernorat', () {
      expect(lieu('La Marsa', ''), isNotNull);
      expect(lieu('La Marsa', '')?.quartier, 'La Marsa');
    });
    test('lieu inconnu', () => expect(lieu('Paris', 'Montmartre'), isNull));
  });

  test('montantEstime sépare les milliers', () {
    expect(montantEstime(230000), '230 000 DT');
    expect(montantEstime(650), '650 DT');
  });

  group('écran', () {
    Future<void> ouvrir(WidgetTester tester, Widget ecran) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ecran));
      await tester.pumpAndSettle();
    }

    testWidgets('champs obligatoires vérifiés', (tester) async {
      await ouvrir(tester, EstimationPrixScreen(service: service));
      await tester.tap(find.text('Estimer le prix'));
      await tester.pump();
      expect(find.text('Choisissez une ville.'), findsOneWidget);
      expect(find.text('Entre 10 et 1500 m².'), findsOneWidget);
    });

    testWidgets('depuis une annonce : pré-rempli, et le loyer revient au formulaire', (tester) async {
      double? recu;
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                recu = await Navigator.of(context).push<double>(
                  MaterialPageRoute(
                    builder: (_) => EstimationPrixScreen(
                      service: service,
                      depuisAnnonce: true,
                      ville: 'Tunis',
                      quartier: 'La Marsa',
                      surface: 80,
                      chambres: 2,
                    ),
                  ),
                );
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Acheter'), findsNothing);
      await tester.tap(find.text('Estimer le prix'));
      await tester.pump();
      expect(find.textContaining('/ mois'), findsOneWidget);
      expect(find.textContaining('La Marsa, Tunis'), findsOneWidget);
      await tester.tap(find.text('Utiliser ce loyer'));
      await tester.pumpAndSettle();
      expect(recu, greaterThan(100));
    });

    testWidgets('une salle de bain à zéro est refusée', (tester) async {
      await ouvrir(tester, EstimationPrixScreen(service: service, ville: 'Tunis', surface: 80));
      await tester.enterText(find.widgetWithText(TextFormField, 'Salles de bain'), '0');
      await tester.tap(find.text('Estimer le prix'));
      await tester.pump();
      expect(find.text('Entre 1 et 10.'), findsOneWidget);
      expect(find.text('Prix estimé'), findsNothing);
    });

    testWidgets('modifier un champ efface l’ancien résultat', (tester) async {
      await ouvrir(tester, EstimationPrixScreen(service: service, ville: 'Tunis', surface: 80));
      await tester.tap(find.text('Estimer le prix'));
      await tester.pump();
      expect(find.text('Prix estimé'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Surface (m²)'), '90');
      await tester.pump();
      expect(find.text('Prix estimé'), findsNothing);
    });
  });
}
