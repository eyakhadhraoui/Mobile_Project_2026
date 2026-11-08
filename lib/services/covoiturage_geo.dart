import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/covoiturage_trajet.dart';
import '../models/enums_covoiturage.dart';

/// Calculs géographiques purs du covoiturage : aucune dépendance Flutter/SQLite.
class CovoiturageGeo {
  static const tuilesOpenStreetMap =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static final centresZones = <String, LatLng>{
    'tunis': const LatLng(36.8065, 10.1815),
    'ariana': const LatLng(36.8665, 10.1647),
    'ben arous': const LatLng(36.7435, 10.2317),
    'la manouba': const LatLng(36.8101, 10.0863),
    'sousse': const LatLng(35.8256, 10.6084),
    'sfax': const LatLng(34.7406, 10.7603),
    'nabeul': const LatLng(36.4513, 10.7357),
    'monastir': const LatLng(35.7643, 10.8113),
    'bizerte': const LatLng(37.2744, 9.8739),
  };
  static LatLng centreZone(String zone) =>
      centresZones[zone.trim().toLowerCase()] ?? centresZones['tunis']!;
  static LatLng _decalage(CovoiturageTrajet t, double direction) {
    final c = centreZone(t.zone);
    final h = t.id.codeUnits.fold<int>(0, (a, b) => a + b);
    final d = .004 + (h % 11) / 10000;
    return LatLng(
      c.latitude + math.sin(h * direction) * d,
      c.longitude + math.cos(h * direction) * d,
    );
  }

  static LatLng positionDepart(CovoiturageTrajet t) =>
      t.departLat != null && t.departLng != null
      ? LatLng(t.departLat!, t.departLng!)
      : _decalage(t, 1);
  static LatLng positionArrivee(CovoiturageTrajet t) =>
      t.arriveeLat != null && t.arriveeLng != null
      ? LatLng(t.arriveeLat!, t.arriveeLng!)
      : _decalage(t, 2);
  static bool estApproximative(CovoiturageTrajet t) =>
      t.departLat == null ||
      t.departLng == null ||
      t.arriveeLat == null ||
      t.arriveeLng == null;
  static double distanceKm(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Kilometer, a, b);
  static GeoBornes calculerBornes(List<LatLng> points) {
    if (points.isEmpty) {
      final c = centreZone('Tunis');
      return GeoBornes(c, c);
    }
    var minLat = points.first.latitude,
        maxLat = minLat,
        minLng = points.first.longitude,
        maxLng = minLng;
    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    return GeoBornes(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  static List<CovoiturageTrajet> trajetsPourCarte(
    List<CovoiturageTrajet> trajets,
    String zoneUtilisateur,
    DateTime maintenant,
  ) =>
      trajets
          .where(
            (t) =>
                t.zone.toLowerCase() == zoneUtilisateur.toLowerCase() &&
                t.statut == StatutTrajetEnum.ouvert &&
                t.departAt.isAfter(maintenant),
          )
          .toList()
        ..sort((a, b) => a.departAt.compareTo(b.departAt));
}

class GeoBornes {
  const GeoBornes(this.sudOuest, this.nordEst);
  final LatLng sudOuest, nordEst;
}
