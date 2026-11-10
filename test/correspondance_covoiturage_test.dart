import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studenthub/models/covoiturage_trajet.dart';
import 'package:studenthub/models/enums_covoiturage.dart';
import 'package:studenthub/services/covoiturage_alertes.dart';
import 'package:studenthub/services/covoiturage_service.dart';
import 'package:studenthub/services/database_helper.dart';

final maintenant = DateTime(2030, 1, 1);

CovoiturageTrajet trajet(
  String id,
  String auteur,
  TypeTrajetEnum type, {
  String depart = 'Ariana',
  String arrivee = 'Sokra',
  String date = '2030-01-07',
  String heure = '08:00',
  int places = 2,
  StatutTrajetEnum statut = StatutTrajetEnum.ouvert,
}) => CovoiturageTrajet(
  id: id,
  auteurId: auteur,
  auteurNom: auteur,
  type: type,
  depart: depart,
  arrivee: arrivee,
  zone: 'Tunis',
  date: date,
  heure: heure,
  places: places,
  statut: statut,
);

CovoiturageTrajet offre({
  String depart = 'Ariana',
  String heure = '08:00',
  String date = '2030-01-07',
  int places = 2,
  StatutTrajetEnum statut = StatutTrajetEnum.ouvert,
}) => trajet('o', 'conducteur', TypeTrajetEnum.offre, depart: depart, heure: heure, date: date, places: places, statut: statut);

CovoiturageTrajet demande({int places = 1, StatutTrajetEnum statut = StatutTrajetEnum.ouvert}) =>
    trajet('d', 'etudiant', TypeTrajetEnum.demande, places: places, statut: statut);

bool convient(CovoiturageTrajet o, CovoiturageTrajet d) => CovoiturageAlertes.offreConvientADemande(o, d, maintenant);

void main() {
  group('règle de correspondance', () {
    test('même trajet, même jour, heures proches et places suffisantes', () {
      expect(convient(offre(), demande()), isTrue);
      expect(convient(offre(heure: '10:00'), demande()), isTrue);
    });

    test('le texte est comparé sans majuscules ni accents', () {
      expect(convient(offre(depart: 'ARIANA ville'), demande()), isTrue);
    });

    test('un autre trajet, jour ou horaire éloigné ne correspond pas', () {
      expect(convient(offre(depart: 'Sfax'), demande()), isFalse);
      expect(convient(offre(date: '2030-01-08'), demande()), isFalse);
      expect(convient(offre(heure: '10:01'), demande()), isFalse);
    });

    test('il faut assez de places', () {
      expect(convient(offre(places: 1), demande(places: 2)), isFalse);
    });

    test('un trajet annulé, complet ou passé ne correspond pas', () {
      expect(convient(offre(statut: StatutTrajetEnum.annule), demande()), isFalse);
      expect(convient(offre(statut: StatutTrajetEnum.complet), demande()), isFalse);
      expect(convient(offre(), demande(statut: StatutTrajetEnum.annule)), isFalse);
      expect(CovoiturageAlertes.offreConvientADemande(offre(), demande(), DateTime(2031)), isFalse);
    });

    test('ses propres trajets ne se répondent pas', () {
      final miens = trajet('d2', 'conducteur', TypeTrajetEnum.demande);
      expect(convient(offre(), miens), isFalse);
    });
  });

  group('vue de chaque compte', () {
    test('le demandeur voit l’offre, le conducteur voit la demande', () {
      final tous = [offre(), demande()];
      final pourEtudiant = CovoiturageAlertes.correspondancesDe('etudiant', tous, maintenant);
      expect(pourEtudiant.single.autre.id, 'o');
      expect(pourEtudiant.single.mien.id, 'd');
      final pourConducteur = CovoiturageAlertes.correspondancesDe('conducteur', tous, maintenant);
      expect(pourConducteur.single.autre.id, 'd');
    });

    test('un tiers ne voit rien', () {
      expect(CovoiturageAlertes.correspondancesDe('autre', [offre(), demande()], maintenant), isEmpty);
    });
  });

  group('correspondances consultées', () {
    late Directory dossier;
    late DatabaseHelper base;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dossier = await Directory.systemTemp.createTemp('correspondance_');
      base = DatabaseHelper.forTests(path: p.join(dossier.path, 'test.db'));
    });

    tearDown(() async {
      await (await base.database).close();
      await dossier.delete(recursive: true);
    });

    test('elles sont mémorisées par compte', () async {
      final service = CovoiturageService(database: base);
      expect(await service.correspondancesVues('a'), isEmpty);
      await service.noterCorrespondancesVues('a', {'d|o'});
      expect(await service.correspondancesVues('a'), {'d|o'});
      expect(await service.correspondancesVues('b'), isEmpty);
    });
  });
}
