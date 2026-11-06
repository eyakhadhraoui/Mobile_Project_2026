import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../core/constants/api_constants.dart';
import '../core/utils/texte.dart';
import 'database_helper.dart';

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
/// SQLite (table `geocodage`) lu avant tout appel. Seule l'adresse est envoyée.
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

  /// GET https://nominatim.openstreetmap.org/search?q=…&format=jsonv2&limit=…&countrycodes=tn
  Future<List<Coordonnees>> _requete(String adresse, {required int limite}) async {
    await _respecterPause();
    final uri = Uri.https(ApiConstants.nominatimHote, '/search', {
      'q': adresse,
      'format': 'jsonv2',
      'limit': '$limite',
      'countrycodes': 'tn',
      'accept-language': 'fr',
    });
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
    final Object? data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const GeocodageIndisponibleException('Réponse de cartographie illisible.');
    }
    if (data is! List) throw const GeocodageIndisponibleException('Réponse de cartographie inattendue.');
    return [
      for (final lieu in data.whereType<Map>())
        if ((double.tryParse('${lieu['lat']}'), double.tryParse('${lieu['lon']}')) case (final lat?, final lon?))
          Coordonnees(lat: lat, lon: lon, libelle: lieu['display_name'] is String ? lieu['display_name'] as String : ''),
    ];
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
