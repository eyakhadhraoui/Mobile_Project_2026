import 'package:flutter_test/flutter_test.dart';
import 'package:studenthub/models/alerte_trajet.dart';
import 'package:studenthub/models/covoiturage_trajet.dart';
import 'package:studenthub/models/enums_covoiturage.dart';
import 'package:studenthub/services/covoiturage_alertes.dart';

final alerte = AlerteTrajet(
  id: 'a',
  userId: 'u',
  depart: 'Túnis centre',
  arrivee: 'Sousse',
  zone: 'Tunis',
  typeCible: TypeTrajetEnum.offre,
  creneau: CreneauAlerteEnum.matin,
  places: 2,
  prixMax: 10,
  dateCreation: '2029-01-01',
);
final trajet = CovoiturageTrajet(
  id: 't',
  auteurId: 'v',
  auteurNom: 'V',
  type: TypeTrajetEnum.offre,
  depart: 'Tunis Centre Ville',
  arrivee: 'Sousse',
  zone: 'Tunis',
  date: '2030-01-07',
  heure: '08:00',
  places: 2,
  prix: 8,
);
void main() {
  test('RG17 accepte texte normalisé et critères compatibles', () {
    expect(
      CovoiturageAlertes.correspond(alerte, trajet, DateTime(2029)).correspond,
      isTrue,
    );
  });
  test('RG16 limite à cinq alertes', () {
    expect(CovoiturageAlertes.peutCreerAlerte(4), isTrue);
    expect(CovoiturageAlertes.peutCreerAlerte(5), isFalse);
  });
  test('refuse zone, auteur et créneau incompatibles', () {
    expect(
      CovoiturageAlertes.correspond(
        alerte,
        trajet.copyWith(zone: 'Sousse'),
        DateTime(2029),
      ).correspond,
      isFalse,
    );
    expect(
      CovoiturageAlertes.correspond(
        alerte,
        CovoiturageTrajet(
          id: 't2',
          auteurId: 'u',
          auteurNom: 'U',
          type: trajet.type,
          depart: trajet.depart,
          arrivee: trajet.arrivee,
          zone: trajet.zone,
          date: trajet.date,
          heure: trajet.heure,
          places: 2,
          prix: 8,
        ),
        DateTime(2029),
      ).correspond,
      isFalse,
    );
  });
}
