import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../core/constants/api_constants.dart';
import '../models/trajet.dart';
import 'database_helper.dart';
import 'geocodage_service.dart';

/// Serveur d'itinéraires injoignable, délai dépassé ou statut HTTP ≠ 200.
class TrajetIndisponibleException implements Exception {
  const TrajetIndisponibleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Réponse OSRM inattendue (JSON invalide, code ≠ « Ok »).
class TrajetReponseInvalideException implements Exception {
  const TrajetReponseInvalideException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Temps de trajet logement → université avec OSRM.
///
/// Le service « table » calcule tous les logements en une requête par mode
/// (par lots de 25). Les résultats sont gardés 30 jours dans SQLite (table
/// `trajets`) et lus avant tout appel. Seules des coordonnées sont envoyées.
class TrajetService {
  TrajetService({
    http.Client? client,
    DatabaseHelper? databaseHelper,
    this.delai = ApiConstants.delaiTrajet,
    this.validite = const Duration(days: 30),
  }) : _client = client ?? http.Client(),
       _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  final http.Client _client;
  final DatabaseHelper _databaseHelper;
  final Duration delai;
  final Duration validite;

  /// « lat,lon » à 5 décimales : clé de cache d'un point.
  static String cle(Coordonnees point) => '${point.lat.toStringAsFixed(5)},${point.lon.toStringAsFixed(5)}';

  /// Trajets depuis chaque logement de [logements] (identifiant → position)
  /// jusqu'à [universite]. Valeur null : aucun itinéraire trouvé.
  Future<Map<String, Trajet?>> calculer({
    required Coordonnees universite,
    required Map<String, Coordonnees> logements,
    required ModeTrajet mode,
  }) async {
    final arrivee = cle(universite);
    final resultats = <String, Trajet?>{};
    final aCalculer = <String, Coordonnees>{};
    final db = await _databaseHelper.database;
    final limite = DateTime.now().toUtc().subtract(validite).toIso8601String();

    for (final MapEntry(key: id, value: position) in logements.entries) {
      final lignes = await db.query(
        'trajets',
        where: 'depart = ? AND arrivee = ? AND mode = ? AND date >= ?',
        whereArgs: [cle(position), arrivee, mode.name, limite],
        limit: 1,
      );
      if (lignes.isEmpty) {
        aCalculer[id] = position;
      } else {
        resultats[id] = _depuisLigne(lignes.first);
      }
    }

    final ids = aCalculer.keys.toList();
    for (var debut = 0; debut < ids.length; debut += ApiConstants.logementsParRequeteTrajet) {
      final lot = ids.skip(debut).take(ApiConstants.logementsParRequeteTrajet).toList();
      final trajets = await _table(universite, [for (final id in lot) aCalculer[id]!], mode);
      for (var i = 0; i < lot.length; i++) {
        resultats[lot[i]] = trajets[i];
        await db.insert('trajets', {
          'depart': cle(aCalculer[lot[i]]!),
          'arrivee': arrivee,
          'mode': mode.name,
          'duree': trajets[i]?.duree.inSeconds.toDouble(),
          'distance': trajets[i]?.distanceMetres,
          'date': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    return resultats;
  }

  /// GET {serveur}/table/v1/driving/{université};{logement1};…
  ///     ?sources=1;2;…&destinations=0&annotations=duration,distance
  /// Coordonnées au format OSRM : longitude,latitude.
  Future<List<Trajet?>> _table(Coordonnees universite, List<Coordonnees> logements, ModeTrajet mode) async {
    String point(Coordonnees c) => '${c.lon.toStringAsFixed(6)},${c.lat.toStringAsFixed(6)}';
    final base = mode == ModeTrajet.pied ? ApiConstants.osrmPied : ApiConstants.osrmVoiture;
    final coordonnees = [universite, ...logements].map(point).join(';');
    final sources = List.generate(logements.length, (i) => '${i + 1}').join(';');
    // Construite à la main : OSRM attend les « ; » et « , » tels quels.
    final uri = Uri.parse(
      '$base/table/v1/driving/$coordonnees?sources=$sources&destinations=0&annotations=duration,distance',
    );

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'User-Agent': ApiConstants.nominatimUserAgent, 'Accept': 'application/json'})
          .timeout(delai);
    } on SocketException {
      throw const TrajetIndisponibleException('Pas de connexion internet.');
    } on TimeoutException {
      throw const TrajetIndisponibleException('Le calcul d’itinéraire ne répond pas.');
    } on http.ClientException {
      throw const TrajetIndisponibleException('Serveur d’itinéraires injoignable.');
    } on HttpException {
      throw const TrajetIndisponibleException('Serveur d’itinéraires injoignable.');
    }
    if (response.statusCode != 200) {
      throw TrajetIndisponibleException('Calcul d’itinéraire indisponible (code ${response.statusCode}).');
    }
    final Object? data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const TrajetReponseInvalideException('Réponse d’itinéraire illisible.');
    }
    if (data is! Map || data['code'] != 'Ok') {
      throw TrajetReponseInvalideException('Itinéraire refusé (${data is Map ? data['code'] : 'réponse inattendue'}).');
    }
    final durees = data['durations'];
    final distances = data['distances'];
    if (durees is! List || distances is! List || durees.length != logements.length || distances.length != logements.length) {
      throw const TrajetReponseInvalideException('Matrice d’itinéraires incomplète.');
    }
    return [
      for (var i = 0; i < logements.length; i++) _cellule(durees[i], distances[i]),
    ];
  }

  /// Ligne i de la matrice : [durée vers l'université] (null si pas de route).
  Trajet? _cellule(Object? ligneDurees, Object? ligneDistances) {
    final duree = ligneDurees is List && ligneDurees.isNotEmpty ? ligneDurees.first : null;
    final distance = ligneDistances is List && ligneDistances.isNotEmpty ? ligneDistances.first : null;
    if (duree is! num || distance is! num) return null;
    return Trajet(duree: Duration(seconds: duree.round()), distanceMetres: distance.toDouble());
  }

  Trajet? _depuisLigne(Map<String, Object?> ligne) {
    final duree = ligne['duree'];
    final distance = ligne['distance'];
    if (duree is! num || distance is! num) return null;
    return Trajet(duree: Duration(seconds: duree.round()), distanceMetres: distance.toDouble());
  }

  void fermer() => _client.close();
}
