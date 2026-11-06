import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/validators.dart';
import '../services/mot_de_passe_service.dart';

/// État de la vérification des fuites de données.
enum EtatVerificationMotDePasse { idle, loading, compromis, sur, indisponible }

/// État du champ « nouveau mot de passe » d'un formulaire (inscription ou
/// changement de mot de passe) : force locale et présence dans des fuites.
///
/// Une instance par écran. Le mot de passe n'est jamais conservé dans un champ :
/// il est seulement passé en paramètre (et capturé par le minuteur d'anti-rebond
/// le temps de l'attente).
class MotDePasseProvider extends ChangeNotifier {
  MotDePasseProvider({MotDePasseService? service, this.antiRebond = const Duration(milliseconds: 500)})
    : _service = service ?? MotDePasseService();

  final MotDePasseService _service;

  /// Délai après la dernière frappe avant d'interroger le service.
  final Duration antiRebond;

  EtatVerificationMotDePasse _etat = EtatVerificationMotDePasse.idle;
  int _nombreFuites = 0;
  ForceMotDePasse? _force;
  Timer? _minuteur;

  /// Numéro de la vérification en cours : une réponse arrivant pour une saisie
  /// plus ancienne est ignorée (annulation de la vérification précédente).
  int _generation = 0;

  /// Vrai si l'état affiché correspond à la saisie actuelle du champ.
  bool _aJour = false;
  bool _ferme = false;

  EtatVerificationMotDePasse get etat => _etat;
  int get nombreFuites => _nombreFuites;

  /// Nombre renvoyé par le dernier appel à [verifierMotDePasse], même si
  /// l'affichage a été réinitialisé depuis par une nouvelle frappe.
  int get nombreDerniereVerification => _nombreDerniereVerification;
  int _nombreDerniereVerification = 0;
  ForceMotDePasse? get force => _force;
  bool get enCours => _etat == EtatVerificationMotDePasse.loading;

  /// À brancher sur `onChanged` du champ : met à jour la force tout de suite et
  /// programme la vérification 500 ms après la dernière frappe.
  void surSaisie(String motDePasse) {
    _minuteur?.cancel();
    _generation++;
    _aJour = false;
    _force = motDePasse.isEmpty ? null : forceMotDePasse(motDePasse);
    _nombreFuites = 0;
    _etat = EtatVerificationMotDePasse.idle;
    notifyListeners();
    // Rien à vérifier si le champ est vide ou trop court.
    if (motDePasse.length < longueurMinimaleMotDePasse) return;
    _minuteur = Timer(antiRebond, () => verifierMotDePasse(motDePasse));
  }

  /// Vérifie immédiatement (fin de l'anti-rebond ou validation du formulaire).
  /// Si le résultat de la saisie actuelle est déjà connu, aucun nouvel appel.
  Future<EtatVerificationMotDePasse> verifierMotDePasse(String motDePasse) async {
    _minuteur?.cancel();
    if (motDePasse.length < longueurMinimaleMotDePasse) return EtatVerificationMotDePasse.idle;
    if (_aJour && (_etat == EtatVerificationMotDePasse.compromis || _etat == EtatVerificationMotDePasse.sur)) {
      _nombreDerniereVerification = _nombreFuites;
      return _etat;
    }
    final generation = ++_generation;
    _etat = EtatVerificationMotDePasse.loading;
    notifyListeners();

    EtatVerificationMotDePasse resultat;
    var nombre = 0;
    try {
      nombre = await _service.nombreDeFuites(motDePasse);
      resultat = nombre > 0 ? EtatVerificationMotDePasse.compromis : EtatVerificationMotDePasse.sur;
    } on ServiceIndisponibleException {
      resultat = EtatVerificationMotDePasse.indisponible;
    }
    _nombreDerniereVerification = nombre;
    // Saisie modifiée entre-temps : ce résultat est périmé.
    if (generation == _generation && !_ferme) {
      _etat = resultat;
      _nombreFuites = nombre;
      // Service indisponible : on retentera à la validation du formulaire.
      _aJour = resultat != EtatVerificationMotDePasse.indisponible;
      notifyListeners();
    }
    return resultat;
  }

  @override
  void notifyListeners() {
    if (!_ferme) super.notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    _minuteur?.cancel();
    super.dispose();
  }
}
