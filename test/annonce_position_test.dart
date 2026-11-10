import 'package:flutter_test/flutter_test.dart';
import 'package:studenthub/models/annonce.dart';

const _json = {
  'id': 'a1',
  'categorie': 'Logement',
  'titre': 'Studio',
  'description': 'd',
  'proprietaireId': 'p1',
};

void main() {
  test('la position est relue, envoyée au serveur et conservée par copyWith', () {
    final annonce = Annonce.fromJson({..._json, 'lat': 36.8, 'lng': 10}); // 10 : entier JSON

    expect(annonce.lat, 36.8);
    expect(annonce.lng, 10.0);
    expect(annonce.toPayload()['lat'], 36.8);
    expect(annonce.toPayload()['lng'], 10.0);
    expect(Annonce.fromJson(annonce.toJson()).lat, 36.8);
    expect(annonce.copyWith(titre: 'Autre').lng, 10.0);
  });

  test('une annonce sans position reste valide', () {
    final annonce = Annonce.fromJson(_json);
    expect(annonce.lat, isNull);
    expect(annonce.lng, isNull);
    expect(annonce.toPayload()['lat'], isNull);
  });

  test('hors logement, aucune position n\'est envoyée', () {
    final annonce = Annonce.fromJson({..._json, 'categorie': 'Avis'});
    expect(annonce.toPayload().containsKey('lat'), isFalse);
  });
}
