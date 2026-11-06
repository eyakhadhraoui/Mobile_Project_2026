import '../core/utils/texte.dart';
import '../models/complaint_model.dart';

/// Plusieurs réclamations sur le même problème : même bâtiment, même
/// catégorie, signalées à moins de 48 h d'intervalle.
class IncidentCollectif {
  const IncidentCollectif({required this.cleBatiment, required this.categorie, required this.reclamations});

  /// Adresse du bâtiment normalisée (sans numéro d'appartement ni de chambre).
  final String cleBatiment;
  final ComplaintCategory categorie;

  /// Réclamations du plus ancien au plus récent signalement.
  final List<ComplaintModel> reclamations;

  /// Identifiant stable : celui du premier signalement.
  String get id => reclamations.first.id;

  /// Adresse affichée (celle du premier signalement).
  String get batiment => reclamations.first.locationId;
  DateTime get debut => reclamations.first.createdAt;
  DateTime get fin => reclamations.last.createdAt;
  int get nombreEtudiants => reclamations.map((r) => r.userId).toSet().length;

  /// Priorité la plus élevée parmi les signalements.
  ComplaintPriority get priorite =>
      reclamations.map((r) => r.priority).reduce((a, b) => a.index >= b.index ? a : b);

  bool contient(String reclamationId) => reclamations.any((r) => r.id == reclamationId);
}

/// Détection des incidents collectifs par règles locales (fonctionne hors ligne).
class IncidentService {
  const IncidentService._();

  /// Écart maximal entre deux signalements consécutifs d'un même incident.
  static const fenetre = Duration(hours: 48);

  /// Nombre minimal de signalements pour parler d'incident collectif.
  static const minimum = 2;

  /// Clé du bâtiment : l'adresse normalisée, sans numéro d'appartement,
  /// de chambre, de porte ni d'étage. « Bloc A, appt 12 » et « bloc a app. 14 »
  /// donnent la même clé « bloc a ».
  static String cleBatiment(String locationId) => normaliserTexte(locationId)
      .replaceAll(
        RegExp(r'\b(appartement|appart|appt|app|apt|chambre|ch|porte|studio|etage|logement|n|no|numero)\s*\d+\s*[a-z]?\b'),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Regroupe les réclamations actives (ni brouillon, ni supprimée, ni résolue).
  static List<IncidentCollectif> regrouper(List<ComplaintModel> reclamations) {
    final groupes = <(String, ComplaintCategory), List<ComplaintModel>>{};
    for (final reclamation in reclamations) {
      if (reclamation.isDraft || reclamation.isDeleted || reclamation.status == ComplaintStatus.cloturee) continue;
      final cle = cleBatiment(reclamation.locationId);
      if (cle.isEmpty) continue;
      groupes.putIfAbsent((cle, reclamation.category), () => []).add(reclamation);
    }
    final incidents = <IncidentCollectif>[];
    for (final MapEntry(key: (batiment, categorie), value: liste) in groupes.entries) {
      liste.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      var courant = <ComplaintModel>[];
      void cloturer() {
        if (courant.length >= minimum) {
          incidents.add(IncidentCollectif(cleBatiment: batiment, categorie: categorie, reclamations: courant));
        }
      }

      for (final reclamation in liste) {
        if (courant.isNotEmpty && reclamation.createdAt.difference(courant.last.createdAt) > fenetre) {
          cloturer();
          courant = [];
        }
        courant.add(reclamation);
      }
      cloturer();
    }
    // Les plus urgents puis les plus récents d'abord.
    incidents.sort((a, b) {
      final priorite = b.priorite.index.compareTo(a.priorite.index);
      return priorite != 0 ? priorite : b.fin.compareTo(a.fin);
    });
    return incidents;
  }
}
