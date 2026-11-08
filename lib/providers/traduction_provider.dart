import 'package:flutter/foundation.dart';

import '../models/complaint_response_model.dart';
import '../services/traduction_service.dart';

enum EtatTraduction { idle, loading, traduit, erreur }

/// État de traduction d'un message.
class TraductionMessage {
  const TraductionMessage({this.etat = EtatTraduction.idle, this.texte, this.afficherTraduction = false, this.source = ''});

  final EtatTraduction etat;
  final String? texte;

  /// Traduction affichée (sinon le texte original).
  final bool afficherTraduction;

  /// Texte original traduit : si le message est modifié, l'état est réinitialisé.
  final String source;
}

/// Traductions des échanges d'une réclamation, pour l'utilisateur qui lit
/// (une instance par écran de détail). À la fermeture de l'écran, les réponses
/// encore attendues sont ignorées.
class TraductionProvider extends ChangeNotifier {
  TraductionProvider({TraductionService? service, required this.langueCible, required this.lecteurId})
    : _service = service ?? TraductionService();

  final TraductionService _service;

  /// Langue du lecteur (son profil).
  final String langueCible;
  final String lecteurId;

  final Map<String, ComplaintResponse> _reponses = {};
  final Map<String, TraductionMessage> _etats = {};
  bool _ferme = false;

  TraductionMessage etat(String reponseId) => _etats[reponseId] ?? const TraductionMessage();

  /// Un message se traduit s'il vient de l'autre partie et d'une autre langue.
  bool peutTraduire(ComplaintResponse reponse) => reponse.authorId != lecteurId && reponse.langue != langueCible;

  /// Met à jour la liste des messages affichés ; l'état d'un message modifié est oublié.
  void definirReponses(List<ComplaintResponse> reponses) {
    _reponses
      ..clear()
      ..addEntries(reponses.map((r) => MapEntry(r.id, r)));
    _etats.removeWhere((id, etat) => _reponses[id] == null || _reponses[id]!.text != etat.source);
  }

  /// Traduit le message [reponseId] dans la langue du lecteur.
  Future<void> traduireReponse(String reponseId) async {
    final reponse = _reponses[reponseId];
    if (reponse == null || !peutTraduire(reponse)) return;
    final actuel = etat(reponseId);
    if (actuel.etat == EtatTraduction.loading) return;
    if (actuel.etat == EtatTraduction.traduit) {
      _etats[reponseId] = TraductionMessage(etat: EtatTraduction.traduit, texte: actuel.texte, afficherTraduction: true, source: actuel.source);
      notifyListeners();
      return;
    }
    _etats[reponseId] = TraductionMessage(etat: EtatTraduction.loading, source: reponse.text);
    notifyListeners();
    TraductionMessage resultat;
    try {
      final texte = await _service.traduireReponse(
        reponseId: reponse.id,
        texte: reponse.text,
        de: reponse.langue,
        vers: langueCible,
      );
      resultat = TraductionMessage(etat: EtatTraduction.traduit, texte: texte, afficherTraduction: true, source: reponse.text);
    } on TraductionException {
      resultat = TraductionMessage(etat: EtatTraduction.erreur, source: reponse.text);
    }
    // Écran fermé ou message modifié entre-temps : résultat ignoré.
    if (_ferme || _etats[reponseId]?.source != reponse.text) return;
    _etats[reponseId] = resultat;
    notifyListeners();
  }

  /// Bascule Original / Traduction.
  void basculerAffichage(String reponseId) {
    final actuel = etat(reponseId);
    if (actuel.etat != EtatTraduction.traduit) return;
    _etats[reponseId] = TraductionMessage(
      etat: EtatTraduction.traduit,
      texte: actuel.texte,
      afficherTraduction: !actuel.afficherTraduction,
      source: actuel.source,
    );
    notifyListeners();
  }

  /// Option « traduction automatique » : traduit les messages pas encore traités.
  Future<void> traduireAutomatiquement() async {
    for (final reponse in _reponses.values.toList()) {
      if (_ferme) return;
      if (peutTraduire(reponse) && etat(reponse.id).etat == EtatTraduction.idle) {
        await traduireReponse(reponse.id);
      }
    }
  }

  @override
  void notifyListeners() {
    if (!_ferme) super.notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    super.dispose();
  }
}
