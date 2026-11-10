import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:studenthub/models/covoiturage_trajet.dart';
import 'package:studenthub/models/enums_covoiturage.dart';
import 'package:studenthub/services/covoiturage_geo.dart';

CovoiturageTrajet trajet({
  String zone = 'Tunis',
  StatutTrajetEnum statut = StatutTrajetEnum.ouvert,
  String date = '2030-01-01',
  double? lat,
}) => CovoiturageTrajet(
  id: 'geo-1',
  auteurId: 'u',
  auteurNom: 'Islem Bhj',
  type: TypeTrajetEnum.offre,
  depart: 'A',
  arrivee: 'B',
  zone: zone,
  date: date,
  heure: '10:00',
  places: 1,
  statut: statut,
  departLat: lat,
  departLng: lat == null ? null : 10.2,
);
void main() {
  test(
    'centre inconnu utilise Tunis et les anciennes données sont approximatives',
    () {
      expect(
        CovoiturageGeo.centreZone('Inconnue'),
        const LatLng(36.8065, 10.1815),
      );
      expect(CovoiturageGeo.estApproximative(trajet()), isTrue);
      expect(
        CovoiturageGeo.positionDepart(trajet()),
        CovoiturageGeo.positionDepart(trajet()),
      );
    },
  );
  test('filtre la zone, le statut et les départs dépassés', () {
    final now = DateTime(2029);
    final result = CovoiturageGeo.trajetsPourCarte(
      [
        trajet(),
        trajet(zone: 'Sousse'),
        trajet(statut: StatutTrajetEnum.complet),
        trajet(date: '2020-01-01'),
      ],
      'Tunis',
      now,
    );
    expect(result, hasLength(1));
  });
  test('calcule distance et bornes', () {
    expect(
      CovoiturageGeo.distanceKm(
        const LatLng(36.8065, 10.1815),
        const LatLng(36.8065, 10.1815),
      ),
      closeTo(0, .001),
    );
    final b = CovoiturageGeo.calculerBornes([
      const LatLng(1, 2),
      const LatLng(3, 4),
    ]);
    expect(b.sudOuest, const LatLng(1, 2));
    expect(b.nordEst, const LatLng(3, 4));
  });
}
