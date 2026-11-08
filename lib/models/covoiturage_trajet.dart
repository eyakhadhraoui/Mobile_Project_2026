import 'enums_covoiturage.dart';

class CovoiturageTrajet {
  const CovoiturageTrajet({
    required this.id,
    required this.auteurId,
    required this.auteurNom,
    required this.type,
    required this.depart,
    required this.arrivee,
    required this.zone,
    required this.date,
    required this.heure,
    required this.places,
    this.prix,
    this.commentaire = '',
    this.statut = StatutTrajetEnum.ouvert,
    this.departLat,
    this.departLng,
    this.arriveeLat,
    this.arriveeLng,
  });
  final String id,
      auteurId,
      auteurNom,
      depart,
      arrivee,
      zone,
      date,
      heure,
      commentaire;
  final TypeTrajetEnum type;
  final int places;
  final double? prix;

  /// Positions saisies volontairement sur la carte, jamais issues du GPS.
  final double? departLat, departLng, arriveeLat, arriveeLng;
  final StatutTrajetEnum statut;
  DateTime get departAt => DateTime.parse('${date}T$heure:00');
  bool get estOffre => type == TypeTrajetEnum.offre;
  Map<String, Object?> toMap() => {
    'id': id,
    'auteurId': auteurId,
    'auteurNom': auteurNom,
    'type': type.name,
    'depart': depart,
    'arrivee': arrivee,
    'zone': zone,
    'date': date,
    'heure': heure,
    'places': places,
    'prix': prix,
    'commentaire': commentaire,
    'statut': statut.name,
    'departLat': departLat,
    'departLng': departLng,
    'arriveeLat': arriveeLat,
    'arriveeLng': arriveeLng,
  };
  factory CovoiturageTrajet.fromMap(Map<String, Object?> m) =>
      CovoiturageTrajet(
        id: m['id']! as String,
        auteurId: m['auteurId']! as String,
        auteurNom: m['auteurNom']! as String,
        type: TypeTrajetEnum.values.byName(m['type']! as String),
        depart: m['depart']! as String,
        arrivee: m['arrivee']! as String,
        zone: m['zone']! as String,
        date: m['date']! as String,
        heure: m['heure']! as String,
        places: m['places']! as int,
        prix: (m['prix'] as num?)?.toDouble(),
        commentaire: m['commentaire'] as String? ?? '',
        statut: StatutTrajetEnum.values.byName(
          m['statut'] as String? ?? 'ouvert',
        ),
        departLat: (m['departLat'] as num?)?.toDouble(),
        departLng: (m['departLng'] as num?)?.toDouble(),
        arriveeLat: (m['arriveeLat'] as num?)?.toDouble(),
        arriveeLng: (m['arriveeLng'] as num?)?.toDouble(),
      );
  CovoiturageTrajet copyWith({
    String? depart,
    String? arrivee,
    String? zone,
    String? date,
    String? heure,
    int? places,
    double? prix,
    String? commentaire,
    StatutTrajetEnum? statut,
    double? departLat,
    double? departLng,
    double? arriveeLat,
    double? arriveeLng,
  }) => CovoiturageTrajet(
    id: id,
    auteurId: auteurId,
    auteurNom: auteurNom,
    type: type,
    depart: depart ?? this.depart,
    arrivee: arrivee ?? this.arrivee,
    zone: zone ?? this.zone,
    date: date ?? this.date,
    heure: heure ?? this.heure,
    places: places ?? this.places,
    prix: prix ?? this.prix,
    commentaire: commentaire ?? this.commentaire,
    statut: statut ?? this.statut,
    departLat: departLat ?? this.departLat,
    departLng: departLng ?? this.departLng,
    arriveeLat: arriveeLat ?? this.arriveeLat,
    arriveeLng: arriveeLng ?? this.arriveeLng,
  );
}
