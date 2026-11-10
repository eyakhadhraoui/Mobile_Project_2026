import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:studenthub/models/annonce.dart';
import 'package:studenthub/models/trajet.dart';
import 'package:studenthub/providers/trajet_provider.dart';
import 'package:studenthub/screens/announcements/trajet_widgets.dart';
import 'package:studenthub/services/geocodage_service.dart';

const _lat = 36.8360;
const _lon = 10.1450;

Map<String, Object?> _lieu(
  String nom, {
  String type = 'university',
  String categorie = 'amenity',
  double lat = _lat,
  double lon = _lon,
}) => {
  'name': nom,
  'type': type,
  'category': categorie,
  'lat': '$lat',
  'lon': '$lon',
};

Annonce _annonce(String id, {double? lat, double? lng, List<FacProche> facs = const []}) => Annonce.fromJson({
  'id': id,
  'categorie': 'Logement',
  'titre': id,
  'description': 'd',
  'statut': 'publiee',
  'proprietaireId': 'p',
  'lat': lat,
  'lng': lng,
  'facsProches': facs.map((f) => f.toJson()).toList(),
});

void main() {
  group('facsDepuis', () {
    test('garde les établissements et écarte le reste', () {
      final facs = GeocodageService.facsDepuis([
        _lieu('FST Faculté des sciences de Tunis'),
        _lieu('ISG Tunis', type: 'college'),
        _lieu('Foyer Universitaire'),
        _lieu('Restaurant universitaire'),
        _lieu('Cité Universitaire Ibn Sina'),
        _lieu('المبيت الجامعي رياض الورد'),
        _lieu('Collège Sahloul', type: 'college'),
        _lieu('Lycée Pilote', type: 'college'),
        _lieu('Centre de langues', type: 'college'),
        _lieu('Ordre des Ingénieurs Tunisiens'),
        _lieu('Faculté des Sciences', type: 'bus_stop', categorie: 'highway'),
        _lieu('University', type: 'place_of_worship'),
        _lieu(''),
      ], _lat, _lon);
      expect(facs.map((f) => f.nom), ['FST Faculté des sciences de Tunis', 'ISG Tunis']);
    });

    test('exclut au-delà du rayon, trie et retire les doublons', () {
      final facs = GeocodageService.facsDepuis([
        _lieu('Institut loin', lat: _lat + 0.05),
        _lieu('Université B', lat: _lat + 0.02),
        _lieu('Université A', lat: _lat + 0.005),
        _lieu('université a', lat: _lat + 0.015),
      ], _lat, _lon);
      expect(facs.map((f) => f.nom), ['Université A', 'Université B']);
      expect(facs.first.lat, closeTo(_lat + 0.005, 1e-9));
    });
  });

  test('facsAutour interroge les universités puis les grandes écoles dans une zone bornée', () async {
    final appels = <Uri>[];
    final service = GeocodageService(
      client: MockClient((request) async {
        appels.add(request.url);
        final nom = request.url.queryParameters['amenity'] == 'university' ? 'Université X' : 'École Y';
        final corps = jsonEncode([_lieu(nom, type: request.url.queryParameters['amenity']!)]);
        return http.Response.bytes(utf8.encode(corps), 200);
      }),
      pause: Duration.zero,
    );
    final facs = await service.facsAutour(_lat, _lon);
    expect(appels.map((u) => u.queryParameters['amenity']), ['university', 'college']);
    expect(appels.first.queryParameters['bounded'], '1');
    expect(facs, hasLength(2));
  });

  test('la liste des facs est relue, envoyée au serveur et mise en cache', () {
    final annonce = _annonce('a', lat: _lat, lng: _lon, facs: const [FacProche(nom: 'FST', lat: 1, lng: 2)]);
    expect(annonce.facsProches.single.nom, 'FST');
    expect(annonce.toPayload()['facsProches'], [
      {'nom': 'FST', 'lat': 1.0, 'lng': 2.0},
    ]);
    expect(Annonce.fromJson(annonce.toJson()).facsProches.single.lng, 2);
    expect(annonce.copyWith(titre: 'x').facsProches, hasLength(1));
  });

  group('annonces proches de la fac de l’étudiant', () {
    late TrajetProvider trajets;
    const fac = Universite(nom: 'FST', lat: _lat, lon: _lon);

    setUp(() => trajets = TrajetProvider());
    tearDown(() => trajets.dispose());

    final sansPosition = _annonce('sans');
    final loin = _annonce('loin', lat: _lat + 0.2, lng: _lon);
    final pres = _annonce('pres', lat: _lat + 0.02, lng: _lon);
    final tresPres = _annonce('tres_pres', lat: _lat + 0.005, lng: _lon);
    final annonces = [sansPosition, loin, pres, tresPres];

    test('passent en tête, de la plus près à la plus loin', () {
      trajets.definirUniversite(fac, const []);
      expect(trajets.appliquer(annonces).map((a) => a.id), ['tres_pres', 'pres', 'sans', 'loin']);
      expect(trajets.presDeMaFac(tresPres), isTrue);
      expect(trajets.presDeMaFac(loin), isFalse);
    });

    test('le rayon est exact : 3,3 km n’est pas à moins de 3 km', () {
      trajets.definirUniversite(fac, const []);
      expect(trajets.presDeMaFac(_annonce('limite', lat: _lat + 0.03, lng: _lon)), isFalse);
      expect(trajets.distanceFacKm(pres), closeTo(2.2, 0.1));
    });

    testWidgets('la pastille s’affiche seulement près de la fac', (tester) async {
      trajets.definirUniversite(fac, const []);
      Widget page(Annonce annonce) => ChangeNotifierProvider.value(
        value: trajets,
        child: MaterialApp(home: Scaffold(body: BadgeFacProche(annonce: annonce))),
      );
      await tester.pumpWidget(page(pres));
      expect(find.textContaining('Près de votre fac'), findsOneWidget);
      await tester.pumpWidget(page(loin));
      expect(find.textContaining('Près de votre fac'), findsNothing);
    });

    test('sans fac choisie, l’ordre ne change pas', () {
      expect(trajets.appliquer(annonces).map((a) => a.id), ['sans', 'loin', 'pres', 'tres_pres']);
    });

    test('une fac listée sur l’annonce compte même hors du rayon direct', () {
      final campus = _annonce(
        'campus',
        lat: _lat + 0.03,
        lng: _lon,
        facs: const [FacProche(nom: 'FST', lat: _lat + 0.002, lng: _lon)],
      );
      trajets.definirUniversite(fac, const []);
      expect(trajets.presDeMaFac(campus), isTrue);
      expect(trajets.appliquer([sansPosition, campus]).first.id, 'campus');
    });

    test('une annonce non publiée ou hors logement n’est pas remontée', () {
      final json = tresPres.toJson();
      final attente = Annonce.fromJson({...json, 'statut': 'enAttente'});
      final avis = Annonce.fromJson({...json, 'categorie': 'Avis'});
      trajets.definirUniversite(fac, const []);
      expect(trajets.presDeMaFac(attente), isFalse);
      expect(trajets.presDeMaFac(avis), isFalse);
    });
  });
}
