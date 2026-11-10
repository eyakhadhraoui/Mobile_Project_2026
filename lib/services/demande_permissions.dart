import '../models/demande_maintenance.dart';
import '../models/user_model.dart';

/// Droits sur les demandes de maintenance, partagés par le service et l'interface.
/// Seul le rôle principal du compte est pris en compte.
class DemandePermissions {
  const DemandePermissions._();

  static bool _gestionnaire(UserRole role) =>
      role == UserRole.proprietaire || role == UserRole.administrateur;

  static bool _auteur(UserRole role, String acteurId, DemandeMaintenance d) =>
      role == UserRole.locataire && d.userId == acteurId;

  static bool _assigne(UserRole role, String acteurId, DemandeMaintenance d) =>
      role == UserRole.prestataire && d.assigneeId == acteurId;

  static bool _terminee(DemandeMaintenance d) =>
      d.statut == StatutMaintenance.terminee;

  static bool voir(UserRole role, String acteurId, DemandeMaintenance d) =>
      _gestionnaire(role) ||
      _auteur(role, acteurId, d) ||
      _assigne(role, acteurId, d);

  static bool creer(UserRole role) => role == UserRole.locataire;

  static bool modifier(UserRole role, String acteurId, DemandeMaintenance d) =>
      _auteur(role, acteurId, d) && !_terminee(d);

  static bool supprimer(UserRole role, String acteurId, DemandeMaintenance d) =>
      _gestionnaire(role) || _auteur(role, acteurId, d);

  static bool marquerResolue(
    UserRole role,
    String acteurId,
    DemandeMaintenance d,
  ) => _auteur(role, acteurId, d) && !_terminee(d);

  /// Statuts proposés dans « Changer le statut ». Le locataire n'y a pas accès :
  /// il passe par « Marquer comme résolu ».
  static List<StatutMaintenance> statutsAutorises(
    UserRole role,
    String acteurId,
    DemandeMaintenance d,
  ) {
    if (_gestionnaire(role)) return StatutMaintenance.values;
    if (_assigne(role, acteurId, d) && !_terminee(d)) {
      return const [StatutMaintenance.enCours, StatutMaintenance.terminee];
    }
    return const [];
  }

  static bool changerStatut(
    UserRole role,
    String acteurId,
    DemandeMaintenance d,
    StatutMaintenance cible,
  ) =>
      statutsAutorises(role, acteurId, d).contains(cible) ||
      (cible == StatutMaintenance.terminee &&
          marquerResolue(role, acteurId, d));

  static bool assigner(UserRole role, DemandeMaintenance d) =>
      _gestionnaire(role) && !_terminee(d);
}
