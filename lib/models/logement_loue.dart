/// Logement occupé par un locataire : demande de location acceptée et non échue.
class LogementLoue {
  const LogementLoue({
    required this.annonceId,
    required this.titre,
    required this.adresse,
    required this.proprietaireId,
    required this.proprietaireNom,
    required this.debut,
    required this.fin,
  });

  final String annonceId;
  final String titre;
  final String adresse;
  final String proprietaireId;
  final String proprietaireNom;

  /// Dates de location au format AAAA-MM-JJ.
  final String debut;
  final String fin;

  Map<String, Object?> toJson(String userId) => {
    'userId': userId,
    'annonceId': annonceId,
    'titre': titre,
    'adresse': adresse,
    'proprietaireId': proprietaireId,
    'proprietaireNom': proprietaireNom,
    'debut': debut,
    'fin': fin,
  };

  factory LogementLoue.fromJson(Map<String, Object?> json) => LogementLoue(
    annonceId: json['annonceId']! as String,
    titre: json['titre']! as String,
    adresse: json['adresse']! as String,
    proprietaireId: json['proprietaireId']! as String,
    proprietaireNom: json['proprietaireNom']! as String,
    debut: json['debut']! as String,
    fin: json['fin']! as String,
  );
}
