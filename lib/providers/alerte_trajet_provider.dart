import 'package:flutter/foundation.dart';

import '../models/alerte_trajet.dart';
import '../models/covoiturage_trajet.dart';
import '../services/alerte_trajet_service.dart';
import '../services/covoiturage_alertes.dart';

class AlerteTrajetProvider extends ChangeNotifier {
  AlerteTrajetProvider({AlerteTrajetService? service})
    : _service = service ?? AlerteTrajetService();
  final AlerteTrajetService _service;
  List<AlerteTrajet> _alertes = [];
  bool _chargement = false;
  String? _erreur;
  List<AlerteTrajet> get alertes => _alertes;
  bool get chargement => _chargement;
  String? get erreur => _erreur;
  Future<void> charger(String? userId) async {
    if (userId == null) return;
    _chargement = true;
    notifyListeners();
    try {
      _alertes = await _service.pourUtilisateur(userId);
    } catch (e) {
      _erreur = e.toString();
    } finally {
      _chargement = false;
      notifyListeners();
    }
  }

  Future<void> enregistrer(AlerteTrajet a) async {
    if (!_alertes.any((x) => x.id == a.id) &&
        !CovoiturageAlertes.peutCreerAlerte(_alertes.length)) {
      throw StateError('Vous avez atteint la limite de 5 alertes');
    }
    final err = CovoiturageAlertes.valider(a);
    if (err != null) throw StateError(err);
    await _service.enregistrer(a);
    await charger(a.userId);
  }

  Future<void> supprimer(AlerteTrajet a) async {
    await _service.supprimer(a.id);
    await charger(a.userId);
  }

  Future<void> actif(AlerteTrajet a, bool v) async {
    await _service.actif(a.id, v);
    await charger(a.userId);
  }

  List<CovoiturageTrajet> correspondances(
    AlerteTrajet a,
    List<CovoiturageTrajet> ts,
  ) => CovoiturageAlertes.trajetsCorrespondants(a, ts, DateTime.now());
}
