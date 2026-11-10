import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../models/annonce.dart';
import '../models/trajet.dart';
import '../services/covoiturage_geo.dart';
import '../services/geocodage_service.dart';
import '../services/trajet_service.dart';

/// Étape du calcul pour une annonce.
enum EtatTrajet { enAttente, calcul, pret, nonLocalise, indisponible }

/// Trajets d'un logement vers l'université de l'étudiant.
class TrajetAnnonce {
  const TrajetAnnonce({this.etat = EtatTrajet.enAttente, this.pied, this.voiture, this.approximatif = false});
  final EtatTrajet etat;
  final Trajet? pied;
  final Trajet? voiture;

  /// Adresse exacte introuvable : position du quartier utilisée.
  final bool approximatif;

  Trajet? selon(ModeTrajet mode) => mode == ModeTrajet.pied ? pied : voiture;

  TrajetAnnonce copyWith({EtatTrajet? etat, Trajet? pied, Trajet? voiture}) =>
      TrajetAnnonce(etat: etat ?? this.etat, pied: pied ?? this.pied, voiture: voiture ?? this.voiture, approximatif: approximatif);
}

/// Temps de trajet logement → université, filtre « à moins de N min » et tri
/// par distance pour la liste des annonces.
class TrajetProvider extends ChangeNotifier {
  TrajetProvider({TrajetService? trajets, GeocodageService? geocodage})
    : _trajets = trajets ?? TrajetService(),
      _geocodage = geocodage ?? GeocodageService();

  final TrajetService _trajets;
  final GeocodageService _geocodage;

  Universite? _universite;
  final Map<String, TrajetAnnonce> _parAnnonce = {};
  String _signature = '';
  int _generation = 0;
  bool _calculEnCours = false;
  int _localises = 0;
  int _aLocaliser = 0;
  String? _erreur;
  bool _ferme = false;

  /// Filtre : afficher seulement les logements à moins de [dureeMax] minutes.
  bool filtreActif = false;
  int dureeMax = 20;
  ModeTrajet modeFiltre = ModeTrajet.pied;

  /// Tri des annonces par distance à l'université (les plus proches d'abord).
  bool triDistance = false;

  Universite? get universite => _universite;
  bool get calculEnCours => _calculEnCours;
  int get localises => _localises;
  int get aLocaliser => _aLocaliser;

  /// Message discret si le calcul n'a pas pu aller au bout (hors ligne…).
  String? get erreur => _erreur;

  TrajetAnnonce? pour(String annonceId) => _parAnnonce[annonceId];

  /// Université lue dans le profil ; un changement relance le calcul.
  void definirUniversite(Universite? universite, List<Annonce> annonces) {
    if (universite == _universite) return;
    _universite = universite;
    _parAnnonce.clear();
    _signature = '';
    _erreur = null;
    if (universite == null) {
      filtreActif = false;
      triDistance = false;
    }
    notifyListeners();
    calculer(annonces);
  }

  void configurerFiltre({bool? actif, int? minutes, ModeTrajet? mode}) {
    filtreActif = actif ?? filtreActif;
    dureeMax = minutes ?? dureeMax;
    modeFiltre = mode ?? modeFiltre;
    notifyListeners();
  }

  void basculerTri() {
    triDistance = !triDistance;
    notifyListeners();
  }

  /// Écart toléré entre une fac listée sur l'annonce et la fac de l'étudiant,
  /// placées chacune sur un point différent du même campus.
  static const _memeFacKm = 0.5;

  /// Distance à vol d'oiseau entre le logement et la fac de l'étudiant.
  double? distanceFacKm(Annonce annonce) {
    final universite = _universite;
    final (lat, lng) = (annonce.lat, annonce.lng);
    if (universite == null || lat == null || lng == null) return null;
    return CovoiturageGeo.distanceExacteKm(LatLng(lat, lng), LatLng(universite.lat, universite.lon));
  }

  /// Vrai si ce logement publié entoure la fac de l'étudiant.
  bool presDeMaFac(Annonce annonce) {
    final universite = _universite;
    final distance = distanceFacKm(annonce);
    if (universite == null || distance == null || !annonce.estLogement || !annonce.estPubliee) return false;
    if (distance <= FacProche.rayonKm) return true;
    final maFac = LatLng(universite.lat, universite.lon);
    return annonce.facsProches.any((fac) => CovoiturageGeo.distanceExacteKm(LatLng(fac.lat, fac.lng), maFac) <= _memeFacKm);
  }

  /// Logements proches de la fac en tête, du plus près au plus loin ; le reste garde son ordre.
  List<Annonce> _prochesEnTete(List<Annonce> annonces) {
    final proches = annonces.where(presDeMaFac).toList();
    if (proches.isEmpty) return annonces;
    final distances = {for (final a in proches) a.id: distanceFacKm(a)!};
    final indexes = {for (var i = 0; i < annonces.length; i++) annonces[i].id: i};
    proches.sort((a, b) {
      final ecart = distances[a.id]!.compareTo(distances[b.id]!);
      return ecart != 0 ? ecart : indexes[a.id]!.compareTo(indexes[b.id]!);
    });
    return [...proches, ...annonces.where((a) => !distances.containsKey(a.id))];
  }

  /// Applique le filtre et le tri à une liste d'annonces déjà filtrée par l'écran.
  /// Avec le filtre actif, seuls les logements dont le trajet est connu et assez court restent.
  List<Annonce> appliquer(List<Annonce> annonces) {
    if (_universite == null) return annonces;
    var resultat = annonces;
    if (filtreActif) {
      final limite = Duration(minutes: dureeMax);
      resultat = [
        for (final a in resultat)
          if (_parAnnonce[a.id]?.selon(modeFiltre) case final trajet? when trajet.duree <= limite) a,
      ];
    }
    if (triDistance) {
      double distance(Annonce a) => _parAnnonce[a.id]?.pied?.distanceMetres ?? _parAnnonce[a.id]?.voiture?.distanceMetres ?? double.infinity;
      // Tri stable : à distance égale (ou inconnue), l'ordre d'origine est gardé.
      final indexes = {for (var i = 0; i < resultat.length; i++) resultat[i].id: i};
      resultat = [...resultat]..sort((a, b) {
        final ecart = distance(a).compareTo(distance(b));
        return ecart != 0 ? ecart : indexes[a.id]!.compareTo(indexes[b.id]!);
      });
      return resultat;
    }
    return _prochesEnTete(resultat);
  }

  /// Calcule les trajets des logements publiés. Sans effet si la liste n'a pas
  /// changé ; un nouvel appel annule le calcul précédent.
  Future<void> calculer(List<Annonce> annonces) async {
    final universite = _universite;
    if (universite == null) return;
    final logements = annonces.where((a) => a.estLogement && a.estPubliee && a.ville.isNotEmpty).toList();
    final signature = logements.map((a) => '${a.id}|${a.adresse}|${a.quartier}|${a.ville}|${a.lat}|${a.lng}').join(';');
    if (signature == _signature) return;
    _signature = signature;
    final generation = ++_generation;
    bool annule() => _ferme || generation != _generation;

    _calculEnCours = true;
    _erreur = null;
    _localises = 0;
    _aLocaliser = logements.length;
    for (final a in logements) {
      _parAnnonce.putIfAbsent(a.id, () => const TrajetAnnonce(etat: EtatTrajet.calcul));
    }
    notifyListeners();

    // 1. Position de chaque logement (cache SQLite, puis Nominatim à 1 req/s).
    final positions = <String, Coordonnees>{};
    for (final annonce in logements) {
      try {
        final (position, approximatif) = await _localiser(annonce);
        if (annule()) return;
        if (position == null) {
          _parAnnonce[annonce.id] = const TrajetAnnonce(etat: EtatTrajet.nonLocalise);
        } else {
          positions[annonce.id] = position;
          _parAnnonce[annonce.id] = TrajetAnnonce(etat: EtatTrajet.calcul, approximatif: approximatif);
        }
      } on GeocodageIndisponibleException catch (error) {
        if (annule()) return;
        _parAnnonce[annonce.id] = const TrajetAnnonce(etat: EtatTrajet.indisponible);
        _erreur = error.message;
      }
      _localises++;
      notifyListeners();
    }

    // 2. Durées à pied et en voiture (cache SQLite, puis OSRM « table »).
    final arrivee = Coordonnees(lat: universite.lat, lon: universite.lon);
    for (final mode in ModeTrajet.values) {
      try {
        final resultats = await _trajets.calculer(universite: arrivee, logements: positions, mode: mode);
        if (annule()) return;
        for (final MapEntry(key: id, value: trajet) in resultats.entries) {
          final actuel = _parAnnonce[id] ?? const TrajetAnnonce();
          _parAnnonce[id] = TrajetAnnonce(
            etat: EtatTrajet.pret,
            pied: mode == ModeTrajet.pied ? trajet : actuel.pied,
            voiture: mode == ModeTrajet.voiture ? trajet : actuel.voiture,
            approximatif: actuel.approximatif,
          );
        }
      } on Exception catch (error) {
        if (annule()) return;
        _erreur = error is TrajetIndisponibleException ? error.message : 'Calcul d’itinéraire indisponible.';
        for (final id in positions.keys) {
          final actuel = _parAnnonce[id]!;
          if (actuel.etat != EtatTrajet.pret) _parAnnonce[id] = actuel.copyWith(etat: EtatTrajet.indisponible);
        }
      }
      notifyListeners();
    }
    _calculEnCours = false;
    notifyListeners();
  }

  /// Nouvel essai demandé par l'utilisateur (après une panne réseau).
  /// Les trajets déjà en cache ne sont pas redemandés.
  Future<void> reessayer(List<Annonce> annonces) {
    _signature = '';
    return calculer(annonces);
  }

  /// Point choisi sur la carte d'abord, puis adresse complète ; à défaut le
  /// quartier (position approximative). La ville seule serait trop imprécise
  /// pour un temps de trajet.
  Future<(Coordonnees?, bool)> _localiser(Annonce annonce) async {
    final (lat, lng) = (annonce.lat, annonce.lng);
    if (lat != null && lng != null) return (Coordonnees(lat: lat, lon: lng), false);
    final complete = [annonce.adresse, annonce.quartier, annonce.ville].where((p) => p.trim().isNotEmpty).join(', ');
    final exacte = await _geocodage.geocoder(complete);
    if (exacte != null) return (exacte, false);
    if (annonce.quartier.trim().isEmpty) return (null, false);
    return (await _geocodage.geocoder('${annonce.quartier}, ${annonce.ville}'), true);
  }

  @override
  void notifyListeners() {
    if (!_ferme) super.notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    _trajets.fermer();
    _geocodage.fermer();
    super.dispose();
  }
}
