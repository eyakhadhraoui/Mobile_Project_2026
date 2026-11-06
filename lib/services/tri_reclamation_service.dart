import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';
import '../core/utils/detecteur_danger.dart';
import '../core/utils/texte.dart';
import '../models/complaint_model.dart';
import 'api_client.dart';

/// Erreur du tri automatique (l'étudiant garde la saisie manuelle).
abstract class TriReclamationException implements Exception {
  const TriReclamationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Serveur non configuré, hors ligne, délai dépassé ou statut HTTP ≠ 200.
class TriIndisponibleException extends TriReclamationException {
  const TriIndisponibleException(super.message);
}

/// L'IA n'a pas renvoyé le JSON attendu.
class TriReponseInvalideException extends TriReclamationException {
  const TriReponseInvalideException(super.message);
}

/// Catégories proposables : celles affichées dans le formulaire.
const categoriesTriables = [
  ComplaintCategory.fuiteEau,
  ComplaintCategory.electricite,
  ComplaintCategory.chauffage,
  ComplaintCategory.equipement,
  ComplaintCategory.proprietaire,
  ComplaintCategory.autre,
];

/// Proposition de l'IA, corrigée par la détection locale des dangers.
class SuggestionTri {
  const SuggestionTri({
    required this.categorie,
    required this.priorite,
    required this.resume,
    this.dangers = const [],
    this.dangerSignaleParIa = false,
  });

  /// Null si l'IA a proposé une catégorie inconnue.
  final ComplaintCategory? categorie;
  final ComplaintPriority priorite;

  /// Titre court proposé (60 caractères maximum), éventuellement vide.
  final String resume;

  /// Dangers détectés localement par mots-clés.
  final List<DangerDetecte> dangers;
  final bool dangerSignaleParIa;

  bool get danger => dangers.isNotEmpty || dangerSignaleParIa;
}

/// Tri d'une réclamation par l'IA du serveur StudentHub (route /chat, réponse
/// { reply }), à qui l'on demande un objet JSON strict.
///
/// Règle de sécurité : un danger détecté localement (gaz, étincelles,
/// inondation…) impose la priorité « urgente », quoi que réponde l'IA.
/// Confidentialité : seuls le titre et la description sont envoyés, après
/// masquage des e-mails et numéros de téléphone ; jamais l'identité de l'auteur.
class TriReclamationService {
  TriReclamationService({http.Client? client, Uri? serveur, this.delai = ApiConstants.delaiTriIa})
    : _client = client ?? http.Client(),
      _serveur = serveur ?? ApiClient.baseUri;

  final http.Client _client;
  final Uri? _serveur;
  final Duration delai;

  Future<SuggestionTri> analyser({required String titre, required String description}) async {
    final dangers = detecterDangers('$titre\n$description');
    final base = _serveur;
    if (base == null) throw const TriIndisponibleException('Serveur non configuré.');
    final uri = base.replace(path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/chat');

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'messages': [
                {'role': 'user', 'content': consigne(titre: titre, description: description)},
              ],
            }),
          )
          .timeout(delai);
    } on SocketException {
      throw const TriIndisponibleException('Pas de connexion internet.');
    } on TimeoutException {
      throw const TriIndisponibleException('L’analyse a pris trop de temps.');
    } on http.ClientException {
      throw const TriIndisponibleException('Serveur injoignable.');
    } on HttpException {
      throw const TriIndisponibleException('Serveur injoignable.');
    }
    if (response.statusCode == 503) throw const TriIndisponibleException('Assistant IA non configuré sur le serveur.');
    if (response.statusCode == 429) throw const TriIndisponibleException('Trop de demandes : réessayez plus tard.');
    if (response.statusCode != 200) throw TriIndisponibleException('Analyse indisponible (code ${response.statusCode}).');

    final Object? enveloppe;
    try {
      enveloppe = json.decode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const TriReponseInvalideException('Réponse du serveur illisible.');
    }
    final reponse = enveloppe is Map ? enveloppe['reply'] : null;
    if (reponse is! String) throw const TriReponseInvalideException('Réponse du serveur inattendue.');
    return interpreter(reponse, dangers: dangers);
  }

  /// Consigne envoyée à l'IA : JSON strict, catégories et priorités autorisées.
  static String consigne({required String titre, required String description}) =>
      'Tu tries une réclamation de logement étudiant. Réponds UNIQUEMENT par un objet JSON '
      'sur une ligne, sans texte autour ni bloc de code, exactement de la forme '
      '{"categorie":"…","priorite":"…","resume":"…","danger":false}.\n'
      '- categorie : une valeur parmi ${categoriesTriables.map((c) => c.name).join(', ')}.\n'
      '- priorite : faible, moyenne ou urgente. urgente si la sécurité est en jeu (gaz, '
      'électricité, incendie, inondation, effondrement) ou si le logement devient inhabitable.\n'
      '- resume : titre en français de 60 caractères maximum.\n'
      '- danger : true seulement en cas de risque pour les personnes.\n'
      'N’inclus aucune donnée personnelle.\n\n'
      'Titre : ${masquerDonneesPersonnelles(titre.trim())}\n'
      'Description : ${masquerDonneesPersonnelles(description.trim())}';

  /// Valide la réponse de l'IA (tolère un bloc ```json``` ou du texte autour)
  /// puis applique la règle des dangers locaux.
  static SuggestionTri interpreter(String reponse, {List<DangerDetecte> dangers = const []}) {
    final debut = reponse.indexOf('{');
    final fin = reponse.lastIndexOf('}');
    if (debut < 0 || fin <= debut) throw const TriReponseInvalideException('L’IA n’a pas renvoyé de JSON.');
    final Object? data;
    try {
      data = json.decode(reponse.substring(debut, fin + 1));
    } on FormatException {
      throw const TriReponseInvalideException('JSON de l’IA invalide.');
    }
    if (data is! Map) throw const TriReponseInvalideException('JSON de l’IA inattendu.');
    final Map<Object?, Object?> champs = data;

    final categorie = categoriesTriables.where((c) => c.name == champs['categorie']).firstOrNull;
    final prioriteIa = ComplaintPriority.values.where((p) => p.name == champs['priorite']).firstOrNull;
    if (categorie == null && prioriteIa == null) {
      throw const TriReponseInvalideException('Ni catégorie ni priorité reconnues.');
    }
    var resume = champs['resume'] is String ? (champs['resume']! as String).trim() : '';
    if (resume.length > 60) resume = '${resume.substring(0, 59).trimRight()}…';
    final dangerIa = champs['danger'] == true;
    final danger = dangers.isNotEmpty || dangerIa;
    return SuggestionTri(
      // Un danger électrique ou une inondation a une catégorie évidente.
      categorie: dangers.map((d) => d.categorie).nonNulls.firstOrNull ?? categorie,
      priorite: danger ? ComplaintPriority.urgente : prioriteIa ?? ComplaintPriority.moyenne,
      resume: resume,
      dangers: dangers,
      dangerSignaleParIa: dangerIa,
    );
  }

  void fermer() => _client.close();
}
