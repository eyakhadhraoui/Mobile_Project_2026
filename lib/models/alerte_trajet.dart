import 'enums_covoiturage.dart';

class AlerteTrajet {
  const AlerteTrajet({
    required this.id,
    required this.userId,
    required this.depart,
    required this.arrivee,
    required this.zone,
    required this.typeCible,
    this.creneau = CreneauAlerteEnum.journee,
    this.jours = const [],
    this.places = 1,
    this.prixMax,
    this.active = true,
    required this.dateCreation,
    this.departLat,
    this.departLng,
    this.arriveeLat,
    this.arriveeLng,
  });
  final String id, userId, depart, arrivee, zone, dateCreation;
  final TypeTrajetEnum typeCible;
  final CreneauAlerteEnum creneau;
  final List<int> jours;
  final int places;
  final double? prixMax, departLat, departLng, arriveeLat, arriveeLng;
  final bool active;
  Map<String, Object?> toMap() => {
    'id': id,
    'userId': userId,
    'depart': depart,
    'arrivee': arrivee,
    'zone': zone,
    'departLat': departLat,
    'departLng': departLng,
    'arriveeLat': arriveeLat,
    'arriveeLng': arriveeLng,
    'typeCible': typeCible.name,
    'creneau': creneau.name,
    'jours': jours.join(','),
    'places': places,
    'prixMax': prixMax,
    'active': active ? 1 : 0,
    'dateCreation': dateCreation,
  };
  factory AlerteTrajet.fromMap(Map<String, Object?> m) => AlerteTrajet(
    id: m['id']! as String,
    userId: m['userId']! as String,
    depart: m['depart']! as String,
    arrivee: m['arrivee']! as String,
    zone: m['zone']! as String,
    typeCible: TypeTrajetEnum.values.byName(m['typeCible']! as String),
    creneau: CreneauAlerteEnum.values.byName(
      m['creneau'] as String? ?? 'journee',
    ),
    jours: (m['jours'] as String? ?? '')
        .split(',')
        .where((v) => v.isNotEmpty)
        .map(int.parse)
        .toList(),
    places: m['places'] as int? ?? 1,
    prixMax: (m['prixMax'] as num?)?.toDouble(),
    active: (m['active'] as int? ?? 1) == 1,
    dateCreation: m['dateCreation']! as String,
    departLat: (m['departLat'] as num?)?.toDouble(),
    departLng: (m['departLng'] as num?)?.toDouble(),
    arriveeLat: (m['arriveeLat'] as num?)?.toDouble(),
    arriveeLng: (m['arriveeLng'] as num?)?.toDouble(),
  );
  AlerteTrajet copyWith({bool? active}) => AlerteTrajet(
    id: id,
    userId: userId,
    depart: depart,
    arrivee: arrivee,
    zone: zone,
    typeCible: typeCible,
    creneau: creneau,
    jours: jours,
    places: places,
    prixMax: prixMax,
    active: active ?? this.active,
    dateCreation: dateCreation,
    departLat: departLat,
    departLng: departLng,
    arriveeLat: arriveeLat,
    arriveeLng: arriveeLng,
  );
}
