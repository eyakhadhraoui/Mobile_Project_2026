import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/alerte_trajet.dart';
import '../models/covoiturage_trajet.dart';
import '../models/enums_covoiturage.dart';
import 'covoiturage_geo.dart';

class ResultatAlerte {
  const ResultatAlerte(this.correspond, this.raisons);
  final bool correspond;
  final List<String> raisons;
}

class CovoiturageAlertes {
  static const rayonKm = 5.0;
  static String normaliser(String s) {
    const a = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
    const b = 'aaaaaaeeeeiiiiooooouuuucn';
    var v = s.trim().toLowerCase();
    for (var i = 0; i < a.length; i++) v = v.replaceAll(a[i], b[i]);
    return v;
  }

  static bool _lieu(
    String a,
    String b,
    double? alat,
    double? alng,
    double? blat,
    double? blng,
  ) {
    final x = normaliser(a), y = normaliser(b);
    if (x.contains(y) || y.contains(x)) return true;
    return alat != null &&
        alng != null &&
        blat != null &&
        blng != null &&
        CovoiturageGeo.distanceKm(LatLng(alat, alng), LatLng(blat, blng)) <=
            rayonKm;
  }

  static bool peutCreerAlerte(int n) => n < 5;
  static String? valider(AlerteTrajet a) {
    if (a.depart.trim().isEmpty || a.arrivee.trim().isEmpty)
      return 'Le départ et l’arrivée sont obligatoires.';
    if (normaliser(a.depart) == normaliser(a.arrivee))
      return 'Le départ et l’arrivée doivent être différents.';
    if (a.places < 1) return 'Le nombre de places doit être au moins 1.';
    if (a.prixMax != null && a.prixMax! < 0)
      return 'Le prix maximum doit être positif.';
    return null;
  }

  static bool _creneau(CreneauAlerteEnum c, int h) => switch (c) {
    CreneauAlerteEnum.matin => h >= 5 && h <= 11,
    CreneauAlerteEnum.apresMidi => h >= 12 && h <= 17,
    CreneauAlerteEnum.soir => h >= 18 && h <= 23,
    CreneauAlerteEnum.journee => true,
  };
  static ResultatAlerte correspond(
    AlerteTrajet a,
    CovoiturageTrajet t,
    DateTime now,
  ) {
    final r = <String>[];
    if (!a.active ||
        a.zone.toLowerCase() != t.zone.toLowerCase() ||
        a.typeCible != t.type ||
        t.statut != StatutTrajetEnum.ouvert ||
        !t.departAt.isAfter(now) ||
        a.userId == t.auteurId)
      return ResultatAlerte(false, r);
    if (!_lieu(
          a.depart,
          t.depart,
          a.departLat,
          a.departLng,
          t.departLat,
          t.departLng,
        ) ||
        !_lieu(
          a.arrivee,
          t.arrivee,
          a.arriveeLat,
          a.arriveeLng,
          t.arriveeLat,
          t.arriveeLng,
        ))
      return ResultatAlerte(false, r);
    r.add('Même trajet');
    if (!_creneau(a.creneau, t.departAt.hour)) return ResultatAlerte(false, r);
    r.add('Créneau respecté');
    if (a.jours.isNotEmpty && !a.jours.contains(t.departAt.weekday))
      return ResultatAlerte(false, r);
    if (a.jours.isNotEmpty) r.add('Jour respecté');
    if (t.places < a.places) return ResultatAlerte(false, r);
    r.add('Places suffisantes');
    if (a.typeCible == TypeTrajetEnum.offre &&
        a.prixMax != null &&
        (t.prix == null || t.prix! > a.prixMax!))
      return ResultatAlerte(false, r);
    if (a.prixMax != null) r.add('Dans votre budget');
    return ResultatAlerte(true, r);
  }

  static List<CovoiturageTrajet> trajetsCorrespondants(
    AlerteTrajet a,
    List<CovoiturageTrajet> ts,
    DateTime now,
  ) =>
      ts.where((t) => correspond(a, t, now).correspond).toList()
        ..sort((x, y) => x.departAt.compareTo(y.departAt));
  static LatLng positionDepartAlerte(AlerteTrajet a) =>
      a.departLat != null && a.departLng != null
      ? LatLng(a.departLat!, a.departLng!)
      : _offset(a, 1);
  static LatLng positionArriveeAlerte(AlerteTrajet a) =>
      a.arriveeLat != null && a.arriveeLng != null
      ? LatLng(a.arriveeLat!, a.arriveeLng!)
      : _offset(a, 2);
  static LatLng _offset(AlerteTrajet a, double d) {
    final c = CovoiturageGeo.centreZone(a.zone);
    final h = a.id.codeUnits.fold(0, (x, y) => x + y);
    return LatLng(
      c.latitude + math.sin(h * d) * .003,
      c.longitude + math.cos(h * d) * .003,
    );
  }
}
