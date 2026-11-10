import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../core/utils/texte.dart';

enum TypeTransaction { louer, vendre }

enum CategorieBien { appartement, maison, colocation }

enum ConfianceEstimation { bonne, moyenne, faible }

class EstimationPrix {
  const EstimationPrix({
    required this.prix,
    required this.bas,
    required this.haut,
    required this.confiance,
    required this.comparables,
    required this.quartierUtilise,
    required this.erreurMediane,
    required this.annoncesModele,
  });

  final double prix;
  final double bas;
  final double haut;
  final ConfianceEstimation confiance;

  /// Annonces du jeu de données situées dans la zone retenue.
  final int comparables;

  /// Faux si le quartier est trop peu représenté : seule la ville compte alors.
  final bool quartierUtilise;

  /// Erreur médiane mesurée sur des annonces que le modèle n'a pas vues (0,23 = 23 %).
  final double erreurMediane;
  final int annoncesModele;
}

/// Catégorie du modèle correspondant à un type de logement de l'annonce.
CategorieBien categorieDepuisTypeLogement(String? type) => switch (type) {
  'Maison' => CategorieBien.maison,
  'Colocation' || 'Chambre' => CategorieBien.colocation,
  _ => CategorieBien.appartement,
};

/// Estimation calculée sur le téléphone, sans réseau : voir
/// tool/entrainement_prix/entrainer.mjs pour la construction du modèle.
class EstimationPrixService {
  EstimationPrixService(this._modele);

  factory EstimationPrixService.depuisJson(String json) =>
      EstimationPrixService(Map<String, dynamic>.from(jsonDecode(json) as Map));

  static EstimationPrixService? _instance;

  static Future<EstimationPrixService> charger() async =>
      _instance ??= EstimationPrixService.depuisJson(await rootBundle.loadString('assets/modele_prix.json'));

  final Map<String, dynamic> _modele;

  Map<String, dynamic> _de(TypeTransaction type) => Map<String, dynamic>.from(_modele[type.name] as Map);

  /// Ordre alphabétique sans tenir compte des accents (Béja avant Bizerte).
  List<String> villes(TypeTransaction type) => (_de(type)['villes'] as Map).keys.cast<String>().toList()
    ..sort((a, b) => normaliserTexte(a).compareTo(normaliserTexte(b)));

  /// Quartiers d'une ville, du mieux représenté au moins bien représenté.
  List<String> quartiers(TypeTransaction type, String ville) {
    final modele = _de(type);
    final connus = Map<String, dynamic>.from(modele['quartiers'] as Map);
    final comptes = Map<String, dynamic>.from(modele['nbQuartier'] as Map);
    final prefixe = '$ville|';
    final cles = connus.keys.where((c) => c.startsWith(prefixe)).toList()
      ..sort((a, b) => (comptes[b] as num).compareTo(comptes[a] as num));
    return cles.map((c) => c.substring(prefixe.length)).toList();
  }

  /// Retrouve la ville et le quartier du jeu de données à partir d'une adresse.
  ({String ville, String? quartier})? resoudreLieu(TypeTransaction type, String ville, String quartier) {
    final saisieVille = normaliserTexte(ville).replaceFirst(RegExp(r'^gouvernorat (de )?'), '');
    final saisieQuartier = normaliserTexte(quartier);
    final villesConnues = villes(type);
    String? villeTrouvee;
    for (final v in villesConnues) {
      if (normaliserTexte(v) == saisieVille) villeTrouvee = v;
    }
    final cles = (_de(type)['quartiers'] as Map).keys.cast<String>().where(
      (c) => villeTrouvee == null || c.startsWith('$villeTrouvee|'),
    );
    String? trouver(String saisie, bool Function(String nom, String saisie) accepte) {
      if (saisie.length < 3) return null;
      for (final cle in cles) {
        if (accepte(normaliserTexte(cle.split('|').last), saisie)) return cle;
      }
      return null;
    }

    bool egal(String nom, String saisie) => nom == saisie;
    bool partiel(String nom, String saisie) => nom.length >= 4 && (saisie.contains(nom) || nom.contains(saisie));
    final cle = trouver(saisieQuartier, egal) ?? trouver(saisieVille, egal) ?? trouver(saisieQuartier, partiel);
    if (cle != null) {
      final parties = cle.split('|');
      return (ville: parties.first, quartier: parties.last);
    }
    return villeTrouvee == null ? null : (ville: villeTrouvee, quartier: null);
  }

  /// Logarithme du prix prédit, ou null si la ville est inconnue du modèle.
  double? logPrix({
    required TypeTransaction type,
    required CategorieBien categorie,
    required String ville,
    String? quartier,
    required double surface,
    int? chambres,
    int? sdb,
  }) {
    final modele = _de(type);
    final effetVille = (modele['villes'] as Map)[ville] as num?;
    if (effetVille == null) return null;
    final c = (modele['fixes'] as List).cast<num>();
    final logS = math.log(surface);
    final effetQuartier = quartier == null ? null : (modele['quartiers'] as Map)['$ville|$quartier'] as num?;
    return c[0] +
        c[1] * logS +
        c[2] * logS * logS +
        c[3] * math.min(chambres ?? 0, 8) +
        (chambres == null ? c[4] : 0) +
        c[5] * math.min(sdb ?? 0, 5) +
        (categorie == CategorieBien.maison ? c[6] : 0) +
        (categorie == CategorieBien.colocation ? c[7] : 0) +
        effetVille +
        (effetQuartier ?? 0);
  }

  EstimationPrix? estimer({
    required TypeTransaction type,
    required CategorieBien categorie,
    required String ville,
    String? quartier,
    required double surface,
    int? chambres,
    int? sdb,
  }) {
    final log = logPrix(
      type: type,
      categorie: categorie,
      ville: ville,
      quartier: quartier,
      surface: surface,
      chambres: chambres ?? chambresCourantes(surface),
      sdb: sdb ?? sdbCourantes(surface),
    );
    if (log == null) return null;
    final modele = _de(type);
    final residus = Map<String, dynamic>.from(modele['residus'] as Map);
    final evaluation = Map<String, dynamic>.from(modele['evaluation'] as Map);
    final parQuartier = quartier == null ? null : (modele['nbQuartier'] as Map)['$ville|$quartier'] as num?;
    final quartierUtilise = parQuartier != null && (modele['quartiers'] as Map).containsKey('$ville|$quartier');
    final comparables = quartierUtilise ? parQuartier.toInt() : ((modele['nbVille'] as Map)[ville] as num? ?? 0).toInt();
    final pas = type == TypeTransaction.louer ? 10.0 : 1000.0;
    double arrondi(double valeur) => (valeur / pas).round() * pas;
    final confiance = categorie == CategorieBien.colocation || comparables < 8
        ? ConfianceEstimation.faible
        : comparables >= 30
        ? ConfianceEstimation.bonne
        : ConfianceEstimation.moyenne;
    return EstimationPrix(
      prix: arrondi(math.exp(log)),
      bas: arrondi(math.exp(log + (residus['bas'] as num))),
      haut: arrondi(math.exp(log + (residus['haut'] as num))),
      confiance: confiance,
      comparables: comparables,
      quartierUtilise: quartierUtilise,
      erreurMediane: (evaluation['erreurMediane'] as num).toDouble(),
      annoncesModele: (evaluation['annonces'] as num).toInt(),
    );
  }

  /// Valeurs médianes des annonces selon la surface, pour un champ laissé vide :
  /// compter zéro salle de bain sous-estimerait le prix d'environ 20 %.
  static int chambresCourantes(double surface) => surface < 75 ? 1 : surface < 105 ? 2 : 3;
  static int sdbCourantes(double surface) => surface < 150 ? 1 : 2;

  /// Exemples écrits à l'entraînement, pour vérifier le calcul de l'application.
  List<Map<String, dynamic>> controle(TypeTransaction type) =>
      (_de(type)['controle'] as List).cast<Map>().map(Map<String, dynamic>.from).toList();
}
