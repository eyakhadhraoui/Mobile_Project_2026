import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants/api_constants.dart';

/// Origine de l'heure renvoyée par [HeureService].
enum SourceHeure { officielle, locale }

/// Résultat d'une demande d'heure : l'instant (en UTC), sa source et, en cas de
/// repli sur l'horloge du téléphone, la raison en français pour l'interface.
class HeureResultat {
  const HeureResultat({required this.heure, required this.source, this.erreur});

  final DateTime heure;
  final SourceHeure source;
  final String? erreur;

  bool get estLocale => source == SourceHeure.locale;
}

/// Heure officielle (fuseau Africa/Tunis) obtenue auprès de TimeAPI avec le
/// package http. En cas d'échec (pas de réseau, délai de 5 s dépassé, statut
/// différent de 200, réponse illisible), on se replie sur DateTime.now().
///
/// Pour ne pas interroger l'API toutes les 30 secondes, l'écart entre l'heure
/// officielle et l'horloge du téléphone est gardé en mémoire pendant [validite].
class HeureService {
  HeureService({
    http.Client? client,
    DateTime Function()? horloge,
    this.validite = const Duration(minutes: 10),
  }) : _client = client ?? http.Client(),
       _horloge = horloge ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _horloge;
  final Duration validite;

  Duration? _decalage;
  DateTime? _decalageObtenuLe;

  static bool _fuseauxCharges = false;

  /// Heure actuelle (UTC) : officielle si possible, sinon celle du téléphone.
  Future<DateTime> heureActuelle() async => (await obtenirHeure()).heure;

  /// Comme [heureActuelle], en indiquant la source. [forcer] ignore l'écart
  /// mémorisé et interroge l'API de nouveau.
  Future<HeureResultat> obtenirHeure({bool forcer = false}) async {
    final local = _horloge();
    final decalage = _decalage;
    final obtenuLe = _decalageObtenuLe;
    if (!forcer && decalage != null && obtenuLe != null && local.difference(obtenuLe).abs() < validite) {
      return HeureResultat(heure: local.add(decalage).toUtc(), source: SourceHeure.officielle);
    }
    try {
      final officielle = await _demanderHeure();
      _decalage = officielle.difference(_horloge());
      _decalageObtenuLe = _horloge();
      return HeureResultat(heure: officielle, source: SourceHeure.officielle);
    } on SocketException {
      return _repli('pas de connexion internet');
    } on TimeoutException {
      return _repli('le service d’heure ne répond pas (délai de 5 s dépassé)');
    } on http.ClientException {
      return _repli('connexion au service d’heure impossible');
    } on HttpException {
      return _repli('connexion au service d’heure impossible');
    } on _StatutHttp catch (error) {
      return _repli('service d’heure indisponible (code ${error.code})');
    } on FormatException {
      return _repli('réponse illisible du service d’heure');
    }
  }

  /// GET https://timeapi.io/api/Time/current/zone?timeZone=Africa/Tunis
  /// Exemple de réponse : {"year":2026,"month":11,"day":5,"hour":14,"minute":3,
  /// "seconds":12,"milliSeconds":345,"dateTime":"2026-11-05T14:03:12.345",
  /// "timeZone":"Africa/Tunis", ...}
  Future<DateTime> _demanderHeure() async {
    final response = await _client.get(ApiConstants.heureActuelleUri).timeout(ApiConstants.delaiHeure);
    if (response.statusCode != 200) throw _StatutHttp(response.statusCode);
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (data is! Map) throw const FormatException('Objet JSON attendu');
    int champ(String nom) {
      final valeur = data[nom];
      if (valeur is! num) throw FormatException('Champ $nom manquant');
      return valeur.toInt();
    }

    // L'API renvoie l'heure « murale » de Tunis, sans décalage : on la convertit
    // en instant UTC grâce à la base des fuseaux horaires.
    _chargerFuseaux();
    final fuseau = data['timeZone'] is String ? data['timeZone'] as String : ApiConstants.fuseauHoraire;
    final tz.Location lieu;
    try {
      lieu = tz.getLocation(fuseau);
    } on tz.LocationNotFoundException {
      throw FormatException('Fuseau inconnu : $fuseau');
    }
    return tz.TZDateTime(
      lieu,
      champ('year'),
      champ('month'),
      champ('day'),
      champ('hour'),
      champ('minute'),
      champ('seconds'),
      data['milliSeconds'] is num ? (data['milliSeconds'] as num).toInt() : 0,
    ).toUtc();
  }

  HeureResultat _repli(String raison) => HeureResultat(
    heure: _horloge().toUtc(),
    source: SourceHeure.locale,
    erreur: 'Heure officielle indisponible : $raison. L’horloge du téléphone est utilisée.',
  );

  static void _chargerFuseaux() {
    if (_fuseauxCharges) return;
    tzdata.initializeTimeZones();
    _fuseauxCharges = true;
  }

  void fermer() => _client.close();
}

class _StatutHttp implements Exception {
  const _StatutHttp(this.code);
  final int code;
}
