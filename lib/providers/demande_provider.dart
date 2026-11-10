import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/demande_maintenance.dart';
import '../models/logement_loue.dart';
import '../models/user_model.dart';
import '../services/demande_permissions.dart';
import '../services/demande_service.dart';
import '../services/logement_loue_service.dart';

class DemandeProvider extends ChangeNotifier {
  DemandeProvider({DemandeService? service, LogementLoueService? logements})
    : _service = service ?? DemandeService(),
      _logementsService = logements ?? LogementLoueService();

  final DemandeService _service;
  final LogementLoueService _logementsService;

  String? _userId;
  UserRole? _role;
  bool _libere = false;
  List<DemandeMaintenance> _demandes = const [];
  List<LogementLoue> _logements = const [];
  bool _chargement = false;
  Object? _erreur;
  String _recherche = '';
  StatutMaintenance? _filtreStatut;
  String? _filtreUrgence;
  String? _filtreCategorie;
  String? _filtrePiece;
  bool _recentsDabord = true;

  String? get utilisateurId => _userId;
  UserRole? get role => _role;
  List<DemandeMaintenance> get demandes => List.unmodifiable(_demandes);
  List<LogementLoue> get logements => List.unmodifiable(_logements);

  int demandesDuLogement(String logementId) =>
      _demandes.where((d) => d.logementId == logementId).length;

  bool get chargement => _chargement;
  Object? get erreur => _erreur;
  String get recherche => _recherche;
  StatutMaintenance? get filtreStatut => _filtreStatut;
  String? get filtreUrgence => _filtreUrgence;
  String? get filtreCategorie => _filtreCategorie;
  String? get filtrePiece => _filtrePiece;
  bool get recentsDabord => _recentsDabord;

  int get nombreFiltresActifs => [
    _filtreStatut,
    _filtreUrgence,
    _filtreCategorie,
    _filtrePiece,
  ].where((filtre) => filtre != null).length;

  List<DemandeMaintenance> get demandesFiltrees {
    final texte = _recherche.trim().toLowerCase();
    final resultat = _demandes.where((d) {
      if (_filtreStatut != null && d.statut != _filtreStatut) return false;
      if (_filtreUrgence != null && d.urgency != _filtreUrgence) return false;
      if (_filtreCategorie != null && d.category != _filtreCategorie) {
        return false;
      }
      if (_filtrePiece != null && d.room != _filtrePiece) return false;
      if (texte.isEmpty) return true;
      return [
        d.title,
        d.description,
        d.residentName,
        d.residentPhone,
      ].any((champ) => champ.toLowerCase().contains(texte));
    }).toList();
    resultat.sort(
      (a, b) => _recentsDabord
          ? b.createdAt.compareTo(a.createdAt)
          : a.createdAt.compareTo(b.createdAt),
    );
    return resultat;
  }

  bool _droit(bool Function(UserRole role, String acteurId) regle) {
    final role = _role;
    final acteurId = _userId;
    return role != null && acteurId != null && regle(role, acteurId);
  }

  bool get peutCreer => _droit((role, _) => DemandePermissions.creer(role));

  bool peutModifier(DemandeMaintenance d) =>
      _droit((role, id) => DemandePermissions.modifier(role, id, d));

  bool peutSupprimer(DemandeMaintenance d) =>
      _droit((role, id) => DemandePermissions.supprimer(role, id, d));

  bool peutMarquerResolue(DemandeMaintenance d) =>
      _droit((role, id) => DemandePermissions.marquerResolue(role, id, d));

  bool peutAssigner(DemandeMaintenance d) =>
      _droit((role, _) => DemandePermissions.assigner(role, d));

  List<StatutMaintenance> statutsAutorises(DemandeMaintenance d) {
    final role = _role;
    final acteurId = _userId;
    if (role == null || acteurId == null) return const [];
    return DemandePermissions.statutsAutorises(role, acteurId, d);
  }

  void setRecherche(String valeur) {
    _recherche = valeur;
    notifyListeners();
  }

  void setFiltreStatut(StatutMaintenance? valeur) {
    _filtreStatut = valeur;
    notifyListeners();
  }

  void setFiltreUrgence(String? valeur) {
    _filtreUrgence = valeur;
    notifyListeners();
  }

  void setFiltreCategorie(String? valeur) {
    _filtreCategorie = valeur;
    notifyListeners();
  }

  void setFiltrePiece(String? valeur) {
    _filtrePiece = valeur;
    notifyListeners();
  }

  void setRecentsDabord(bool valeur) {
    _recentsDabord = valeur;
    notifyListeners();
  }

  void _viderFiltres() {
    _filtreStatut = null;
    _filtreUrgence = null;
    _filtreCategorie = null;
    _filtrePiece = null;
  }

  void reinitialiserFiltres() {
    _viderFiltres();
    notifyListeners();
  }

  /// Appelé par le ProxyProvider pendant le build : le travail est reporté.
  void definirUtilisateur(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _role = null;
    _demandes = const [];
    _logements = const [];
    _erreur = null;
    if (userId == null) {
      _recherche = '';
      _viderFiltres();
    }
    Future.microtask(() {
      if (_libere || userId != _userId) return;
      if (userId == null) {
        notifyListeners();
      } else {
        unawaited(charger());
      }
    });
  }

  Future<void> charger() async {
    final userId = _userId;
    if (userId == null) return;
    _chargement = true;
    _erreur = null;
    notifyListeners();
    try {
      final role = await _service.roleDe(userId);
      final demandes = await _service.lister(userId);
      if (userId != _userId) return;
      _role = role;
      _demandes = demandes;
      unawaited(chargerLogements());
    } catch (error) {
      if (userId != _userId) return;
      _erreur = error;
      debugPrint('Chargement des demandes impossible : $error');
    } finally {
      if (userId == _userId) {
        _chargement = false;
        notifyListeners();
      }
    }
  }

  /// Actualise les logements du locataire. Hors ligne, la copie locale est utilisée.
  Future<void> chargerLogements() async {
    final userId = _userId;
    if (userId == null || _role != UserRole.locataire) return;
    try {
      await _logementsService.synchroniser(userId);
    } catch (error) {
      debugPrint('Synchronisation des logements impossible : $error');
    }
    try {
      final logements = await _logementsService.lister(userId);
      if (userId != _userId) return;
      _logements = logements;
      notifyListeners();
    } catch (error) {
      debugPrint('Lecture des logements impossible : $error');
    }
  }

  String get _acteur {
    final userId = _userId;
    if (userId == null) throw const DemandeAccesRefuse();
    return userId;
  }

  Future<void> ajouter(DemandeMaintenance demande) async {
    await _service.ajouter(_acteur, demande);
    await charger();
  }

  Future<void> modifier(DemandeMaintenance demande) async {
    await _service.modifier(_acteur, demande);
    await charger();
  }

  Future<void> supprimer(String id) async {
    await _service.supprimer(_acteur, id);
    await charger();
  }

  Future<void> changerStatut(String id, StatutMaintenance statut) async {
    await _service.changerStatut(_acteur, id, statut);
    await charger();
  }

  Future<void> assigner(String id, String? prestataireId) async {
    await _service.assigner(_acteur, id, prestataireId);
    await charger();
  }

  Future<List<PrestataireDemande>> listerPrestataires() =>
      _service.listerPrestataires(_acteur);

  @override
  void notifyListeners() {
    if (!_libere) super.notifyListeners();
  }

  @override
  void dispose() {
    _libere = true;
    super.dispose();
  }
}
