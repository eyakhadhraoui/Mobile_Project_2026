import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';

/// Le service Pwned Passwords ne peut pas répondre (hors ligne, délai dépassé,
/// statut HTTP différent de 200). Le message ne contient jamais le mot de passe
/// ni son empreinte.
class ServiceIndisponibleException implements Exception {
  const ServiceIndisponibleException(this.raison);
  final String raison;

  @override
  String toString() => 'Vérification des fuites indisponible ($raison).';
}

/// Vérifie si un mot de passe figure dans des fuites de données connues,
/// grâce à l'API Pwned Passwords et au principe du « k-anonymat » :
/// 1. on calcule le SHA-1 du mot de passe, en majuscules (40 caractères) ;
/// 2. on envoie SEULEMENT ses 5 premiers caractères ;
/// 3. le serveur renvoie tous les suffixes connus commençant par ce préfixe ;
/// 4. la comparaison avec les 35 caractères restants se fait sur le téléphone.
///
/// Sécurité : le mot de passe et son empreinte complète ne sont jamais envoyés,
/// affichés, journalisés ni stockés. Ils ne vivent que dans cette méthode.
class MotDePasseService {
  MotDePasseService({http.Client? client, this.delai = ApiConstants.delaiFuites})
    : _client = client ?? http.Client();

  /// À partir de ce nombre d'apparitions, le mot de passe est refusé.
  static const seuilBlocage = 100;

  final http.Client _client;
  final Duration delai;

  /// Nombre d'apparitions du mot de passe dans les fuites connues (0 si absent).
  /// Lève [ServiceIndisponibleException] si le service ne répond pas.
  Future<int> nombreDeFuites(String motDePasse) async {
    final empreinte = sha1.convert(utf8.encode(motDePasse)).toString().toUpperCase();
    final prefixe = empreinte.substring(0, 5);
    final suffixe = empreinte.substring(5);

    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('${ApiConstants.pwnedPasswordsBaseUrl}/range/$prefixe'),
            // Le padding ajoute de fausses lignes (nombre 0) pour que la taille
            // de la réponse ne révèle rien du préfixe demandé.
            headers: const {'Add-Padding': 'true'},
          )
          .timeout(delai);
    } on SocketException {
      throw const ServiceIndisponibleException('pas de connexion');
    } on TimeoutException {
      throw const ServiceIndisponibleException('délai dépassé');
    } on http.ClientException {
      throw const ServiceIndisponibleException('connexion impossible');
    } on HttpException {
      throw const ServiceIndisponibleException('connexion impossible');
    }
    if (response.statusCode != 200) {
      throw ServiceIndisponibleException('code ${response.statusCode}');
    }
    return compterSuffixe(response.body, suffixe);
  }

  /// Cherche [suffixe] dans une réponse « SUFFIXE:NOMBRE », une ligne par hash.
  /// Les lignes de remplissage (nombre 0) et les lignes illisibles sont ignorées.
  static int compterSuffixe(String reponse, String suffixe) {
    for (final ligne in const LineSplitter().convert(reponse)) {
      final separateur = ligne.indexOf(':');
      if (separateur < 0) continue;
      if (ligne.substring(0, separateur).trim().toUpperCase() != suffixe) continue;
      final nombre = int.tryParse(ligne.substring(separateur + 1).trim()) ?? 0;
      if (nombre > 0) return nombre;
    }
    return 0;
  }

  void fermer() => _client.close();
}
