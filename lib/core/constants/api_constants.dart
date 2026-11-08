/// Services web publics utilisés par l’application (Annonces, Utilisateurs, Réclamations).
/// Aucune clé d'API n'est nécessaire.
class ApiConstants {
  const ApiConstants._();

  /// URL de base de TimeAPI (heure officielle).
  static const heureBaseUrl = 'https://timeapi.io/api';

  /// Fuseau horaire de référence de l'application.
  static const fuseauHoraire = 'Africa/Tunis';

  /// Délai maximal d'attente de la réponse du service d'heure.
  static const delaiHeure = Duration(seconds: 5);

  /// Adresse complète : GET {heureBaseUrl}/Time/current/zone?timeZone=Africa/Tunis
  static Uri get heureActuelleUri => Uri.parse(
    '$heureBaseUrl/Time/current/zone',
  ).replace(queryParameters: {'timeZone': fuseauHoraire});

  /// URL de base de Pwned Passwords (Have I Been Pwned), sans clé d'API.
  /// Seuls les 5 premiers caractères du SHA-1 sont envoyés : GET {base}/range/{prefixe5}
  static const pwnedPasswordsBaseUrl = 'https://api.pwnedpasswords.com';

  /// Délai maximal d'attente de la vérification des fuites.
  static const delaiFuites = Duration(seconds: 8);

  /// API de traduction MyMemory (sans clé) : GET https://{hote}/get?q=…&langpair=fr|ru
  static const traductionHote = 'api.mymemory.translated.net';
  static const traductionChemin = '/get';

  /// Délai maximal par requête de traduction.
  static const delaiTraduction = Duration(seconds: 8);

  /// Taille maximale d'un morceau de texte envoyé à MyMemory (requêtes limitées).
  static const tailleMorceauTraduction = 400;

  /// Géocodage OpenStreetMap (Nominatim), sans clé : GET https://{hote}/search?q=…&format=jsonv2
  /// Règles d'usage : une requête par seconde au maximum, User-Agent identifiant
  /// l'application (sans donnée personnelle), résultats mis en cache.
  static const nominatimHote = 'nominatim.openstreetmap.org';
  static const nominatimUserAgent = 'StudentHub/1.0 (application etudiante Flutter)';
  static const nominatimPause = Duration(milliseconds: 1100);

  /// Tuiles de la carte OpenStreetMap (attribution obligatoire à l'écran).
  static const tuilesOsm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Tri automatique par l'IA du serveur (route /chat) : un modèle de langue
  /// répond plus lentement qu'une API classique.
  static const delaiTriIa = Duration(seconds: 25);

  /// Itinéraires OSRM (sans clé). Le serveur de démonstration ne calcule que des
  /// trajets en voiture (le profil « foot » y renvoie des temps de voiture) :
  /// la marche utilise le serveur OSRM piéton de FOSSGIS, même API.
  /// GET {base}/table/v1/driving/{lon,lat;lon,lat…}?sources=…&destinations=0
  static const osrmVoiture = 'https://router.project-osrm.org';
  static const osrmPied = 'https://routing.openstreetmap.de/routed-foot';
  static const delaiTrajet = Duration(seconds: 10);

  /// Logements calculés par requête « table » (serveurs publics : rester léger).
  static const logementsParRequeteTrajet = 25;
}
