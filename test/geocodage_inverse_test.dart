import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studenthub/services/geocodage_service.dart';

GeocodageService _service(http.Response Function(Uri) repondre) =>
    GeocodageService(
      client: MockClient((request) async => repondre(request.url)),
      pause: Duration.zero,
    );

void main() {
  group('libelleCourt', () {
    test('combine le lieu et la ville', () {
      expect(
        GeocodageService.libelleCourt({
          'name': 'Avenue Habib Bourguiba',
          'address': {'road': 'Avenue Habib Bourguiba', 'city': 'Tunis'},
        }),
        'Avenue Habib Bourguiba, Tunis',
      );
    });

    test('se rabat sur la rue quand le lieu n\'a pas de nom', () {
      expect(
        GeocodageService.libelleCourt({
          'name': '',
          'address': {'road': 'Rue de Marseille', 'town': 'Ariana'},
        }),
        'Rue de Marseille, Ariana',
      );
    });

    test('ne répète pas un nom identique à la ville', () {
      expect(
        GeocodageService.libelleCourt({
          'name': 'Sousse',
          'address': {'city': 'Sousse'},
        }),
        'Sousse',
      );
    });

    test('utilise display_name sans détail d\'adresse', () {
      expect(
        GeocodageService.libelleCourt({'display_name': 'Gouvernorat de Sfax'}),
        'Gouvernorat de Sfax',
      );
    });

    test('rend null pour une réponse vide', () {
      expect(GeocodageService.libelleCourt({}), isNull);
    });
  });

  group('adresseDepuis', () {
    test('sépare numéro et rue, quartier et ville', () {
      final lieu = GeocodageService.adresseDepuis({
        'name': 'Résidence Jasmin',
        'address': {
          'house_number': '12',
          'road': 'Rue de Marseille',
          'suburb': 'Lafayette',
          'city': 'Tunis',
        },
      });
      expect(lieu.adresse, '12 Rue de Marseille');
      expect(lieu.quartier, 'Lafayette');
      expect(lieu.ville, 'Tunis');
    });

    test('sans rue, prend le nom du lieu ; un champ inconnu reste vide', () {
      final lieu = GeocodageService.adresseDepuis({
        'name': 'Cité El Ghazala',
        'address': {'town': 'Ariana'},
      });
      expect(lieu.adresse, 'Cité El Ghazala');
      expect(lieu.quartier, isEmpty);
      expect(lieu.ville, 'Ariana');
    });

    test('un quartier identique à la ville n\'est pas répété', () {
      final lieu = GeocodageService.adresseDepuis({
        'address': {'road': 'Rue A', 'suburb': 'Sousse', 'city': 'Sousse'},
      });
      expect(lieu.quartier, isEmpty);
    });

    test('adresseDe rend null pour un point inconnu', () async {
      final lieu = await _service(
        (_) => http.Response('{"error":"Unable to geocode"}', 200),
      ).adresseDe(0, 0);
      expect(lieu, isNull);
    });
  });

  group('lieuDe', () {
    test('interroge /reverse avec le point choisi', () async {
      late Uri appel;
      final lieu = await _service((url) {
        appel = url;
        return http.Response.bytes(
          '{"name":"Lac 2","address":{"city":"Tunis"}}'.codeUnits,
          200,
        );
      }).lieuDe(36.85, 10.27);

      expect(lieu, 'Lac 2, Tunis');
      expect(appel.path, '/reverse');
      expect(appel.queryParameters['lat'], '36.85');
      expect(appel.queryParameters['lon'], '10.27');
    });

    test('rend null quand OpenStreetMap ne connaît pas le point', () async {
      final lieu = await _service(
        (_) => http.Response('{"error":"Unable to geocode"}', 200),
      ).lieuDe(0, 0);
      expect(lieu, isNull);
    });

    test('signale un service indisponible', () {
      expect(
        _service((_) => http.Response('', 503)).lieuDe(36.8, 10.1),
        throwsA(isA<GeocodageIndisponibleException>()),
      );
    });
  });
}
