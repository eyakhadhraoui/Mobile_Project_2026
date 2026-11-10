import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:sqflite/sqflite.dart';

import '../core/constants/api_constants.dart';
import '../core/utils/texte.dart';
import '../models/annonce.dart';
import 'covoiturage_geo.dart';
import 'database_helper.dart';

/// Champs d'adresse déduits d'un point choisi sur la carte.
class AdresseLieu {
  const AdresseLieu({required this.adresse, required this.quartier, required this.ville});
  final String adresse;
  final String quartier;
  final String ville;
}

/// Position d'une adresse de logement.
class Coordonnees {
  const Coordonnees({required this.lat, required this.lon, this.libelle = ''});
  final double lat;
  final double lon;

  /// Adresse complète trouvée par OpenStreetMap.
  final String libelle;
}

/// Nominatim injoignable, délai dépassé, statut ≠ 200 ou réponse illisible.
class GeocodageIndisponibleException implements Exception {
  const GeocodageIndisponibleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Conversion des adresses de logement en coordonnées (Nominatim, OpenStreetMap).
///
/// Règles d'usage de Nominatim respectées : une requête par seconde au
/// maximum, User-Agent identifiant l'application (sans e-mail), et cache
/// SQLite (table `geocodage`) lu avant tout appel. Seule l'adresse, ou le point
/// choisi sur la carte, est envoyée.
class GeocodageService {
  GeocodageService({
    http.Client? client,
    DatabaseHelper? databaseHelper,
    this.pause = ApiConstants.nominatimPause,
    this.delai = const Duration(seconds: 8),
    this.reessaiIntrouvable = const Duration(days: 7),
  }) : _client = client ?? http.Client(),
       _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  final http.Client _client;
  final DatabaseHelper _databaseHelper;

  /// Intervalle minimal entre deux requêtes à Nominatim.
  final Duration pause;
  final Duration delai;

  /// Une adresse introuvable est redemandée après ce délai (elle a pu être corrigée côté OSM).
  final Duration reessaiIntrouvable;

  DateTime? _derniereRequete;

  /// Clé de cache d'une adresse : texte normalisé (casse, accents, ponctuation).
  static String cle(String adresse) => normaliserTexte(adresse);

  /// Coordonnées de [adresse], ou null si OpenStreetMap ne la connaît pas.
  Future<Coordonnees?> geocoder(String adresse) async {
    final cleAdresse = cle(adresse);
    if (cleAdresse.isEmpty) return null;
    final db = await _databaseHelper.database;
    final enCache = await db.query('geocodage', where: 'adresse = ?', whereArgs: [cleAdresse], limit: 1);
    if (enCache.isNotEmpty) {
      final ligne = enCache.first;
      if (ligne['introuvable'] != 1) {
        return Coordonnees(
          lat: (ligne['lat']! as num).toDouble(),
          lon: (ligne['lon']! as num).toDouble(),
          libelle: ligne['libelle'] as String? ?? '',
        );
      }
      final date = DateTime.tryParse(ligne['date'] as String? ?? '');
      if (date != null && DateTime.now().toUtc().difference(date) < reessaiIntrouvable) return null;
    }

    final resultat = await _rechercher(adresse.trim());
    await db.insert('geocodage', {
      'adresse': cleAdresse,
      'lat': resultat?.lat,
      'lon': resultat?.lon,
      'libelle': resultat?.libelle,
      'introuvable': resultat == null ? 1 : 0,
      'date': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return resultat;
  }

  /// Géocode plusieurs adresses (une seule fois chacune), dans l'ordre.
  /// Une panne réseau arrête la boucle : les adresses déjà trouvées sont rendues.
  Future<({Map<String, Coordonnees?> positions, bool incomplet})> geocoderTout(
    Iterable<String> adresses, {
    void Function(int faites, int total)? progression,
  }) async {
    final uniques = <String, String>{};
    for (final adresse in adresses) {
      uniques.putIfAbsent(cle(adresse), () => adresse);
    }
    final positions = <String, Coordonnees?>{};
    var faites = 0;
    for (final entree in uniques.entries) {
      try {
        positions[entree.key] = await geocoder(entree.value);
      } on GeocodageIndisponibleException {
        return (positions: positions, incomplet: true);
      }
      progression?.call(++faites, uniques.length);
    }
    return (positions: positions, incomplet: false);
  }

  /// Plusieurs lieux correspondant à [texte] (choix de l'université). Non mis en cache.
  Future<List<Coordonnees>> rechercher(String texte, {int limite = 5}) =>
      _requete(texte.trim(), limite: limite);

  Future<Coordonnees?> _rechercher(String adresse) async {
    final resultats = await _requete(adresse, limite: 1);
    return resultats.isEmpty ? null : resultats.first;
  }

  /// Nom court du lieu situé à ([lat], [lon]), ou null si OpenStreetMap n'y connaît rien.
  /// Non mis en cache : chaque point choisi sur la carte est différent.
  Future<String?> lieuDe(double lat, double lon) async {
    final data = await _inverse(lat, lon);
    return data == null ? null : libelleCourt(data);
  }

  /// Adresse, quartier et ville du point choisi, ou null si le point est inconnu.
  Future<AdresseLieu?> adresseDe(double lat, double lon) async {
    final data = await _inverse(lat, lon);
    if (data == null) return null;
    final lieu = adresseDepuis(data);
    return lieu.adresse.isEmpty && lieu.ville.isEmpty ? null : lieu;
  }

  /// Facs situées à moins de [rayonKm] du point, de la plus proche à la plus loin.
  /// Une requête par type d'établissement, sans cache : chaque point est différent.
  Future<List<FacProche>> facsAutour(double lat, double lon, {double rayonKm = FacProche.rayonKm}) async {
    final ecartLat = rayonKm / 111.32;
    final ecartLon = rayonKm / (111.32 * math.cos(lat * math.pi / 180));
    final resultats = <Map>[];
    for (final amenity in const ['university', 'college']) {
      final data = await _getJson('/search', {
        'amenity': amenity,
        'format': 'jsonv2',
        'viewbox': '${lon - ecartLon},${lat + ecartLat},${lon + ecartLon},${lat - ecartLat}',
        'bounded': '1',
        'limit': '40',
        'countrycodes': 'tn',
        'accept-language': 'fr',
      });
      if (data is! List) throw const GeocodageIndisponibleException('Réponse de cartographie inattendue.');
      resultats.addAll(data.whereType<Map>());
    }
    return facsDepuis(resultats, lat, lon, rayonKm: rayonKm);
  }

  /// OpenStreetMap classe aussi foyers, restaurants universitaires, collèges et lycées.
  static final _horsFac = RegExp(
    r'\b(foyer|cite|restaurant|amphi|lycee|college|primaire|middle school|bibliotheque|residence|ordre)\b|مبيت|مطعم',
  );
  static final _etudesSuperieures = RegExp(
    r'\b(universite|university|faculte|institut|ecole|polytechnique|iset|isg|ihec|enit|insat)\b',
  );
  static const _maxFacs = 20;

  /// Garde les vrais établissements nommés du rayon, sans doublon de nom.
  static List<FacProche> facsDepuis(List<Map> resultats, double lat, double lon, {double rayonKm = FacProche.rayonKm}) {
    final origine = LatLng(lat, lon);
    final parNom = <String, ({FacProche fac, double km})>{};
    for (final lieu in resultats) {
      final type = lieu['type'];
      final nom = _premier([lieu['name']]);
      final latitude = double.tryParse('${lieu['lat']}');
      final longitude = double.tryParse('${lieu['lon']}');
      if (lieu['category'] != 'amenity' || (type != 'university' && type != 'college')) continue;
      if (nom == null || latitude == null || longitude == null) continue;
      final cle = normaliserTexte(nom);
      if (_horsFac.hasMatch(cle) || (type == 'college' && !_etudesSuperieures.hasMatch(cle))) continue;
      final km = CovoiturageGeo.distanceExacteKm(origine, LatLng(latitude, longitude));
      if (km > rayonKm || (parNom[cle]?.km ?? double.infinity) <= km) continue;
      parNom[cle] = (fac: FacProche(nom: nom, lat: latitude, lng: longitude), km: km);
    }
    final tries = parNom.values.toList()..sort((a, b) => a.km.compareTo(b.km));
    return [for (final item in tries.take(_maxFacs)) item.fac];
  }

  Future<Map?> _inverse(double lat, double lon) async {
    final data = await _getJson('/reverse', {
      'lat': '$lat',
      'lon': '$lon',
      'format': 'jsonv2',
      'zoom': '18',
      'addressdetails': '1',
      'accept-language': 'fr',
    });
    if (data is! Map) throw const GeocodageIndisponibleException('Réponse de cartographie inattendue.');
    return data['error'] != null ? null : data;
  }

  static String? _premier(List<Object?> valeurs) {
    for (final valeur in valeurs) {
      if (valeur is String && valeur.trim().isNotEmpty) return valeur.trim();
    }
    return null;
  }

  static String? _ville(Map adresse) =>
      _premier([adresse['city'], adresse['town'], adresse['village'], adresse['municipality'], adresse['state']]);

  /// « Rue ou lieu, Ville » à partir d'une réponse Nominatim.
  static String? libelleCourt(Map lieu) {
    final details = lieu['address'];
    final Map adresse = details is Map ? details : const {};
    final endroit = _premier([lieu['name'], adresse['road'], adresse['neighbourhood'], adresse['suburb']]);
    final ville = _ville(adresse);
    final parties = {?endroit, ?ville};
    return parties.isEmpty ? _premier([lieu['display_name']]) : parties.join(', ');
  }

  /// Découpe une réponse Nominatim ; un champ inconnu reste vide.
  static AdresseLieu adresseDepuis(Map lieu) {
    final details = lieu['address'];
    final Map adresse = details is Map ? details : const {};
    final rue = _premier([adresse['road'], adresse['pedestrian'], adresse['footway']]);
    final numero = _premier([adresse['house_number']]);
    final ville = _ville(adresse) ?? '';
    final quartier = _premier([adresse['suburb'], adresse['neighbourhood'], adresse['quarter'], adresse['city_district']]) ?? '';
    return AdresseLieu(
      adresse: rue == null ? (_premier([lieu['name'], adresse['neighbourhood'], adresse['suburb']]) ?? '') : [?numero, rue].join(' '),
      quartier: quartier == ville ? '' : quartier,
      ville: ville,
    );
  }

  /// GET https://nominatim.openstreetmap.org/search?q=…&format=jsonv2&limit=…&countrycodes=tn
  Future<List<Coordonnees>> _requete(String adresse, {required int limite}) async {
    final data = await _getJson('/search', {
      'q': adresse,
      'format': 'jsonv2',
      'limit': '$limite',
      'countrycodes': 'tn',
      'accept-language': 'fr',
    });
    if (data is! List) throw const GeocodageIndisponibleException('Réponse de cartographie inattendue.');
    return [
      for (final lieu in data.whereType<Map>())
        if ((double.tryParse('${lieu['lat']}'), double.tryParse('${lieu['lon']}')) case (final lat?, final lon?))
          Coordonnees(lat: lat, lon: lon, libelle: lieu['display_name'] is String ? lieu['display_name'] as String : ''),
    ];
  }

  Future<Object?> _getJson(String chemin, Map<String, String> parametres) async {
    await _respecterPause();
    final uri = Uri.https(ApiConstants.nominatimHote, chemin, parametres);
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'User-Agent': ApiConstants.nominatimUserAgent, 'Accept': 'application/json'})
          .timeout(delai);
    } on SocketException {
      throw const GeocodageIndisponibleException('Pas de connexion internet.');
    } on TimeoutException {
      throw const GeocodageIndisponibleException('Le service de cartographie ne répond pas.');
    } on http.ClientException {
      throw const GeocodageIndisponibleException('Service de cartographie injoignable.');
    } on HttpException {
      throw const GeocodageIndisponibleException('Service de cartographie injoignable.');
    }
    if (response.statusCode != 200) {
      throw GeocodageIndisponibleException('Service de cartographie indisponible (code ${response.statusCode}).');
    }
    try {
      return json.decode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const GeocodageIndisponibleException('Réponse de cartographie illisible.');
    }
  }

  /// Une requête par seconde au maximum (règle de Nominatim).
  Future<void> _respecterPause() async {
    final derniere = _derniereRequete;
    if (derniere != null) {
      final attente = pause - DateTime.now().difference(derniere);
      if (attente > Duration.zero) await Future<void>.delayed(attente);
    }
    _derniereRequete = DateTime.now();
  }

  void fermer() => _client.close();
}
