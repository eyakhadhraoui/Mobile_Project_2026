/// Mode de déplacement entre le logement et l'université.
enum ModeTrajet { pied, voiture }

extension ModeTrajetLibelle on ModeTrajet {
  String get libelle => switch (this) {
    ModeTrajet.pied => 'à pied',
    ModeTrajet.voiture => 'en voiture',
  };
}

/// Durée et distance d'un trajet calculé par OSRM (voiture : hors trafic).
class Trajet {
  const Trajet({required this.duree, required this.distanceMetres});
  final Duration duree;
  final double distanceMetres;
}

/// Université choisie par l'étudiant (enregistrée dans ses préférences).
class Universite {
  const Universite({required this.nom, required this.lat, required this.lon});
  final String nom;
  final double lat;
  final double lon;

  static const clePreference = 'universite';

  Map<String, dynamic> toMap() => {'nom': nom, 'lat': lat, 'lon': lon};

  /// Lit l'université des préférences du profil (null si absente ou invalide).
  static Universite? depuisPreferences(Map<String, dynamic>? preferences) {
    final valeur = preferences?[clePreference];
    if (valeur is! Map) return null;
    final nom = valeur['nom'];
    final lat = valeur['lat'];
    final lon = valeur['lon'];
    if (nom is! String || lat is! num || lon is! num) return null;
    return Universite(nom: nom, lat: lat.toDouble(), lon: lon.toDouble());
  }

  @override
  bool operator ==(Object other) => other is Universite && other.nom == nom && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(nom, lat, lon);
}

/// « 12 min », « 1 h 05 ».
String formatDuree(Duration duree) {
  final minutes = (duree.inSeconds / 60).round();
  if (minutes < 60) return '${minutes < 1 ? 1 : minutes} min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}

/// « 850 m », « 1,2 km ».
String formatDistance(double metres) =>
    metres < 1000 ? '${(metres / 10).round() * 10} m' : '${(metres / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
