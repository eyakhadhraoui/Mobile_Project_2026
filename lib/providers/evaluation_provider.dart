import 'package:flutter/foundation.dart';
import '../models/evaluation_trajet.dart';
import '../services/evaluation_service.dart';
class EvaluationProvider extends ChangeNotifier {
  EvaluationProvider({EvaluationService? service}) : _service = service ?? EvaluationService(); final EvaluationService _service;
  Future<Reputation> reputation(String userId) => _service.reputation(userId);
  Future<List<EvaluationTrajet>> recues(String userId) => _service.recues(userId);
  Future<bool> existe(String trajetId, String evaluateurId, String evalueId) => _service.existe(trajetId, evaluateurId, evalueId);
  Future<void> creer(EvaluationTrajet e) async { await _service.creer(e); notifyListeners(); }
}
