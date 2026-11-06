import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../core/constants/api_constants.dart';
import '../core/constants/langues.dart';
import 'api_client.dart';
import 'database_helper.dart';

/// Erreur de traduction (message en français, sans le texte traduit).
abstract class TraductionException implements Exception {
  const TraductionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Pas de réseau, délai dépassé ou statut HTTP différent de 200.
class TraductionIndisponibleException extends TraductionException {
  const TraductionIndisponibleException(super.message);
}

/// Réponse JSON qui n'a pas la forme attendue.
class TraductionReponseInvalideException extends TraductionException {
  const TraductionReponseInvalideException(super.message);
}

/// MyMemory a répondu mais refuse la traduction (responseStatus ≠ 200 :
/// quota quotidien atteint, paire de langues invalide…).
class TraductionRefuseeException extends TraductionException {
  const TraductionRefuseeException(super.message);
}

/// Traduction des échanges d'une réclamation.
///
/// 1. Lecture du cache SQLite (table `traductions`) ;
/// 2. API MyMemory, texte découpé aux fins de phrases en morceaux de
///    400 caractères maximum, traduits dans l'ordre puis recollés ;
/// 3. en cas d'échec, route /chat du serveur StudentHub (consigne de traduction fidèle).
///
/// Confidentialité : seuls le texte du message et la paire de langues sont
/// envoyés. Jamais d'e-mail (MyMemory accepte un paramètre « de » qui n'est
/// pas utilisé), d'identifiant ni de nom.
class TraductionService {
  TraductionService({
    http.Client? client,
    DatabaseHelper? databaseHelper,
    Uri? serveur,
    bool utiliserServeur = true,
    this.delai = ApiConstants.delaiTraduction,
    this.delaiServeur = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
       _serveur = utiliserServeur ? (serveur ?? ApiClient.baseUri) : null;

  /// MyMemory limite aussi la requête en octets (500) : marge pour les
  /// alphabets non latins, dont chaque lettre occupe 2 octets en UTF-8.
  static const octetsMaxMorceau = 450;

  /// Morceaux envoyés au repli /chat (le serveur accepte 2000 caractères).
  static const tailleMorceauServeur = 1500;

  final http.Client _client;
  final DatabaseHelper _databaseHelper;
  final Uri? _serveur;
  final Duration delai;

  /// Le repli passe par un modèle de langue, plus lent qu'une API de traduction.
  final Duration delaiServeur;

  // ---------------------------------------------------------------------------
  // Cache
  // ---------------------------------------------------------------------------

  /// Traduction du message [reponseId] en [vers] : cache d'abord, API ensuite.
  Future<String> traduireReponse({
    required String reponseId,
    required String texte,
    required String de,
    required String vers,
  }) async {
    final enCache = await lireCache(reponseId, vers);
    if (enCache != null) return enCache;
    final traduction = await traduire(texte, de: de, vers: vers);
    await _enregistrerCache(reponseId, vers, traduction);
    return traduction;
  }

  Future<String?> lireCache(String reponseId, String langue) async {
    try {
      final db = await _databaseHelper.database;
      final rows = await db.query(
        'traductions',
        columns: ['texte_traduit'],
        where: 'reponse_id = ? AND langue = ?',
        whereArgs: [reponseId, langue],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['texte_traduit'] as String;
    } on DatabaseException {
      return null; // Cache indisponible : on traduit quand même.
    }
  }

  Future<void> _enregistrerCache(String reponseId, String langue, String texte) async {
    try {
      final db = await _databaseHelper.database;
      await db.insert('traductions', {
        'reponse_id': reponseId,
        'langue': langue,
        'texte_traduit': texte,
        'date': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } on DatabaseException {
      // Le cache est une optimisation : son échec n'empêche pas l'affichage.
    }
  }

  // ---------------------------------------------------------------------------
  // Traduction
  // ---------------------------------------------------------------------------

  /// Traduit [texte] de la langue [de] vers [vers] (codes fr, en, ar, ru, es, de, tr).
  Future<String> traduire(String texte, {required String de, required String vers}) async {
    if (de == vers || texte.trim().isEmpty) return texte;
    try {
      return await _parParagraphes(
        texte,
        (morceau) => _myMemory(morceau, de, vers),
        max: ApiConstants.tailleMorceauTraduction,
        octets: octetsMaxMorceau,
      );
    } on TraductionException catch (erreurMyMemory) {
      if (_serveur == null) rethrow;
      try {
        return await _parParagraphes(
          texte,
          (morceau) => _viaServeur(morceau, de, vers),
          max: tailleMorceauServeur,
          octets: tailleMorceauServeur * 4,
        );
      } on TraductionException {
        throw erreurMyMemory; // Les deux voies ont échoué : on signale la première.
      }
    }
  }

  /// Traduit paragraphe par paragraphe (retours à la ligne conservés), chaque
  /// paragraphe étant découpé en morceaux traduits dans l'ordre.
  Future<String> _parParagraphes(
    String texte,
    Future<String> Function(String morceau) traduireMorceau, {
    required int max,
    required int octets,
  }) async {
    final paragraphes = <String>[];
    for (final paragraphe in texte.split('\n')) {
      final morceaux = decouperParagraphe(paragraphe, max: max, octets: octets);
      final traduits = <String>[];
      for (final morceau in morceaux) {
        traduits.add((await traduireMorceau(morceau)).trim());
      }
      paragraphes.add(traduits.join(' '));
    }
    return paragraphes.join('\n');
  }

  /// GET https://api.mymemory.translated.net/get?q=…&langpair=fr|ru
  Future<String> _myMemory(String morceau, String de, String vers) async {
    final uri = Uri.https(ApiConstants.traductionHote, ApiConstants.traductionChemin, {
      'q': morceau,
      'langpair': '$de|$vers',
    });
    final response = await _envoyer(() => _client.get(uri, headers: const {'Accept': 'application/json'}), delai);
    final Object? data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const TraductionReponseInvalideException('Réponse de traduction illisible.');
    }
    if (data is! Map) throw const TraductionReponseInvalideException('Réponse de traduction inattendue.');
    final statut = data['responseStatus'];
    final code = statut is num ? statut.toInt() : int.tryParse('$statut');
    if (code == null) throw const TraductionReponseInvalideException('Statut de traduction manquant.');
    if (code != 200) throw TraductionRefuseeException('Traduction refusée par le service (code $code).');
    final donnees = data['responseData'];
    final traduit = donnees is Map ? donnees['translatedText'] : null;
    if (traduit is! String || traduit.trim().isEmpty) {
      throw const TraductionReponseInvalideException('Traduction absente de la réponse.');
    }
    return decoderEntites(traduit);
  }

  /// Repli : POST {ACCOUNT_API_URL}/chat avec { messages: [{ role: user, content }] },
  /// réponse { reply }. Seul le texte à traduire est transmis.
  Future<String> _viaServeur(String morceau, String de, String vers) async {
    final base = _serveur!;
    final uri = base.replace(path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/chat');
    final consigne =
        'Traduis fidèlement le texte suivant du ${nomLangue(de)} vers le ${nomLangue(vers)}. '
        'Conserve le sens exact, le ton et les nombres. Réponds uniquement par la traduction, '
        'sans guillemets, sans introduction ni commentaire.\n\nTexte :\n$morceau';
    final response = await _envoyer(
      () => _client.post(
        uri,
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'messages': [
            {'role': 'user', 'content': consigne},
          ],
        }),
      ),
      delaiServeur,
    );
    final Object? data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const TraductionReponseInvalideException('Réponse du serveur illisible.');
    }
    final reponse = data is Map ? data['reply'] : null;
    if (reponse is! String || reponse.trim().isEmpty) {
      throw const TraductionReponseInvalideException('Traduction absente de la réponse du serveur.');
    }
    return reponse.trim();
  }

  /// Exécute la requête avec délai et convertit les erreurs réseau en exceptions typées.
  Future<http.Response> _envoyer(Future<http.Response> Function() requete, Duration limite) async {
    final http.Response response;
    try {
      response = await requete().timeout(limite);
    } on SocketException {
      throw const TraductionIndisponibleException('Pas de connexion internet.');
    } on TimeoutException {
      throw const TraductionIndisponibleException('Le service de traduction ne répond pas.');
    } on http.ClientException {
      throw const TraductionIndisponibleException('Connexion au service de traduction impossible.');
    } on HttpException {
      throw const TraductionIndisponibleException('Connexion au service de traduction impossible.');
    }
    if (response.statusCode != 200) {
      throw TraductionIndisponibleException('Service de traduction indisponible (code ${response.statusCode}).');
    }
    return response;
  }

  // ---------------------------------------------------------------------------
  // Découpage
  // ---------------------------------------------------------------------------

  /// Découpe [texte] en morceaux d'au plus [max] caractères (et [octets] en
  /// UTF-8), de préférence aux fins de phrases, sans rien perdre ni réordonner.
  static List<String> decouper(
    String texte, {
    int max = ApiConstants.tailleMorceauTraduction,
    int octets = octetsMaxMorceau,
  }) => [for (final paragraphe in texte.split('\n')) ...decouperParagraphe(paragraphe, max: max, octets: octets)];

  static List<String> decouperParagraphe(String paragraphe, {required int max, required int octets}) {
    bool tient(String s) => s.length <= max && utf8.encode(s).length <= octets;
    // Fin de phrase : ponctuation suivie d'un espace ou de la fin (pas « 3.5 »).
    final phrases = RegExp(r'.+?(?:[.!?…]+(?=\s|$)|$)')
        .allMatches(paragraphe)
        .map((m) => m.group(0)!.trim())
        .where((phrase) => phrase.isNotEmpty);
    final morceaux = <String>[];
    var courant = '';
    void ajouter(String partie) {
      final essai = courant.isEmpty ? partie : '$courant $partie';
      if (tient(essai)) {
        courant = essai;
        return;
      }
      if (courant.isNotEmpty) morceaux.add(courant);
      courant = partie;
    }

    for (final phrase in phrases) {
      if (tient(phrase)) {
        ajouter(phrase);
        continue;
      }
      // Phrase trop longue : découpe aux espaces, puis coupe franche si un mot dépasse.
      for (final mot in phrase.split(RegExp(r'\s+'))) {
        var reste = mot;
        while (!tient(reste)) {
          var coupe = reste.length < max ? reste.length : max;
          while (coupe > 1 && !tient(reste.substring(0, coupe))) {
            coupe--;
          }
          ajouter(reste.substring(0, coupe));
          reste = reste.substring(coupe);
        }
        if (reste.isNotEmpty) ajouter(reste);
      }
    }
    if (courant.isNotEmpty) morceaux.add(courant);
    return morceaux;
  }

  /// MyMemory renvoie parfois des entités HTML (&#39;, &quot;…).
  static String decoderEntites(String texte) => texte
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  void fermer() => _client.close();
}
