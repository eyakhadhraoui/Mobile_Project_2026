import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/complaint_model.dart';
import '../models/complaint_response_model.dart';
import '../services/complaint_service.dart';
import '../services/incident_service.dart';

class ComplaintProvider extends ChangeNotifier {
  ComplaintProvider({ComplaintService? service})
    : _service = service ?? ComplaintService();

  final ComplaintService _service;
  StreamSubscription<List<ComplaintModel>>? _subscription;
  List<ComplaintModel> _complaints = const [];
  bool _isLoading = false;
  String? _error;

  List<ComplaintModel> get complaints => _complaints;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pendingSyncCount => _complaints.where((item) => !item.isDraft && item.syncStatus == ComplaintSyncStatus.pending).length;
  int get draftCount => _complaints.where((item) => item.isDraft).length;

  List<IncidentCollectif>? _incidents;

  /// Incidents collectifs parmi les réclamations chargées (recalculés à chaque changement).
  List<IncidentCollectif> get incidents => _incidents ??= IncidentService.regrouper(_complaints);

  IncidentCollectif? incidentPour(String complaintId) {
    for (final incident in incidents) {
      if (incident.contient(complaintId)) return incident;
    }
    return null;
  }

  /// Réponse commune du propriétaire : le même message (et éventuellement le
  /// même statut) est ajouté à chaque réclamation de l'incident ; chaque
  /// étudiant le reçoit dans ses échanges, traduisible dans sa langue.
  Future<void> repondreIncident(
    IncidentCollectif incident, {
    required String texte,
    required String auteurId,
    required String langue,
    ComplaintStatus? statut,
  }) async {
    for (final reclamation in incident.reclamations) {
      await _service.addResponse(
        complaintId: reclamation.id,
        authorId: auteurId,
        authorRole: ComplaintAuthorRole.proprietaire,
        text: texte,
        langue: langue,
      );
      if (statut != null && statut != reclamation.status) await _service.updateStatus(reclamation.id, statut);
    }
    unawaited(_service.syncNow());
  }

  void watch(String userId) {
    _watch(_service.watchForUser(userId));
  }

  void watchAll() {
    _watch(_service.watchAll());
  }

  void _watch(Stream<List<ComplaintModel>> source) {
    _subscription?.cancel();
    _complaints = const [];
    _incidents = null;
    _isLoading = true;
    notifyListeners();
    _subscription = source.listen(
      (complaints) {
        _complaints = complaints;
        _incidents = null;
        _isLoading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object error) {
        _error = error.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> create(ComplaintModel complaint) => _service.create(complaint);

  Future<bool> syncNow() async {
    final synced = await _service.syncNow();
    notifyListeners();
    return synced;
  }

  Future<ComplaintModel?> complaintById(String id) => _service.getById(id);

  Future<void> update(ComplaintModel complaint) => _service.update(complaint);

  Future<void> updateStatus(String complaintId, ComplaintStatus status) =>
      _service.updateStatus(complaintId, status);

  Future<void> delete(String complaintId, {required String userId}) =>
      _service.delete(complaintId, userId: userId);

  /// Échanges d'une réclamation (mis à jour hors ligne et après synchronisation).
  Stream<List<ComplaintResponse>> watchResponses(String complaintId) => _service.watchResponses(complaintId);

  /// Ajoute un message puis tente de l'envoyer tout de suite (sinon il reste
  /// dans la file locale jusqu'au retour du réseau).
  Future<void> addResponse({
    required String complaintId,
    required String authorId,
    required ComplaintAuthorRole authorRole,
    required String text,
    required String langue,
  }) async {
    await _service.addResponse(
      complaintId: complaintId,
      authorId: authorId,
      authorRole: authorRole,
      text: text,
      langue: langue,
    );
    unawaited(_service.syncNow());
  }

  Future<void> updateResponse(String responseId, String text, {required String authorId}) async {
    await _service.updateResponse(responseId, text, authorId: authorId);
    unawaited(_service.syncNow());
  }

  Future<void> deleteResponse(String responseId, {required String authorId}) async {
    await _service.deleteResponse(responseId, authorId: authorId);
    unawaited(_service.syncNow());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
