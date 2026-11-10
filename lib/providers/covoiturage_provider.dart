import 'package:flutter/foundation.dart';

import '../models/covoiturage_trajet.dart';
import '../models/reservation_trajet.dart';
import '../services/covoiturage_service.dart';
import '../services/covoiturage_alertes.dart';
import '../services/covoiturage_geo.dart';
import '../models/enums_covoiturage.dart';

class CovoiturageProvider extends ChangeNotifier {
  CovoiturageProvider({CovoiturageService? service})
    : _service = service ?? CovoiturageService();
  final CovoiturageService _service;
  List<CovoiturageTrajet> _trajets = [];
  CompteCovoiturage? _compte;
  bool _chargement = false;
  String? _erreur;
  Set<String> _correspondancesVues = {};
  TypeTrajetEnum? _filtreCarte;
  CovoiturageTrajet? _trajetCarteSelectionne;
  List<CovoiturageTrajet> get trajets => _trajets;

  /// Offres et demandes des autres compatibles avec celles du compte connecté.
  List<CorrespondanceTrajet> get correspondances {
    final compte = _compte;
    if (compte == null) return const [];
    return CovoiturageAlertes.correspondancesDe(compte.id, _trajets, DateTime.now());
  }

  int get correspondancesNonVues =>
      correspondances.where((c) => !_correspondancesVues.contains(c.cle)).length;

  Future<void> marquerCorrespondancesVues() async {
    final compte = _compte;
    if (compte == null || correspondancesNonVues == 0) return;
    _correspondancesVues = {..._correspondancesVues, ...correspondances.map((c) => c.cle)};
    notifyListeners();
    await _service.noterCorrespondancesVues(compte.id, _correspondancesVues);
  }

  CompteCovoiturage? get compte => _compte;
  bool get chargement => _chargement;
  String? get erreur => _erreur;
  TypeTrajetEnum? get filtreCarte => _filtreCarte;
  CovoiturageTrajet? get trajetCarteSelectionne => _trajetCarteSelectionne;
  List<CovoiturageTrajet> get trajetsCarte {
    final compte = _compte;
    if (compte == null) return const [];
    final liste = CovoiturageGeo.trajetsPourCarte(
      _trajets,
      compte.zone,
      DateTime.now(),
    );
    return _filtreCarte == null
        ? liste
        : liste.where((t) => t.type == _filtreCarte).toList();
  }

  void definirFiltreCarte(TypeTrajetEnum? valeur) {
    _filtreCarte = valeur;
    notifyListeners();
  }

  void selectionnerTrajetCarte(CovoiturageTrajet? trajet) {
    _trajetCarteSelectionne = trajet;
    notifyListeners();
  }

  Future<void> initialiser({required String? sessionUserId}) => _run(() async {
    await _service.initialiser();
    _compte = sessionUserId == null
        ? null
        : await _service.compteUtilisateur(sessionUserId);
    await _service.actualiserEtatEtRappels();
    await _charger();
  });
  Future<void> changerZone(String zone) => _run(() async {
    final c = _compte;
    if (c == null) return;
    await _service.definirZone(c.id, zone);
    _compte = CompteCovoiturage(c.id, c.nom, zone);
  });
  Future<void> actualiser() => _run(_charger);
  Future<void> publier(CovoiturageTrajet t) => _run(() async {
    await _service.publier(t);
    await _charger();
  });
  Future<void> modifier(CovoiturageTrajet a, CovoiturageTrajet n) =>
      _run(() async {
        await _service.modifier(a, n);
        await _charger();
      });
  Future<void> demander(CovoiturageTrajet t, int places) => _run(() async {
    final c = _compte!;
    await _service.demander(
      trajet: t,
      participantId: c.id,
      participantNom: c.nom,
      places: places,
    );
    await _charger();
  });
  Future<void> repondre(
    CovoiturageTrajet t,
    ReservationTrajet r,
    bool accepter,
  ) => _run(() async {
    await _service.repondre(trajet: t, reservation: r, accepter: accepter);
    await _charger();
  });
  Future<void> annulerTrajet(CovoiturageTrajet t) => _run(() async {
    await _service.annulerTrajet(t);
    await _charger();
  });
  Future<void> annulerReservation(CovoiturageTrajet t, ReservationTrajet r) =>
      _run(() async {
        await _service.annulerReservation(t, r);
        await _charger();
      });
  Future<List<ReservationTrajet>> reservations(String trajetId) =>
      _service.reservations(trajetId);
  Future<List<ReservationTrajet>> mesReservations() =>
      _service.mesReservations(_compte!.id);
  Future<void> _charger() async {
    _trajets = await _service.trajets();
    final compte = _compte;
    if (compte != null) {
      _correspondancesVues = await _service.correspondancesVues(compte.id);
    }
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    _chargement = true;
    _erreur = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      _erreur = e
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Invalid argument(s): ', '');
      rethrow;
    } finally {
      _chargement = false;
      notifyListeners();
    }
  }
}
