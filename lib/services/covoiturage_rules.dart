import '../models/covoiturage_trajet.dart';
import '../models/enums_covoiturage.dart';
import '../models/reservation_trajet.dart';

/// Règles pures du module : facilement testables sans SQLite ni Flutter.
class CovoiturageRules {
  static int placesConfirmees(Iterable<ReservationTrajet> reservations) => reservations.where((r) => r.statut == StatutReservationEnum.confirmee).fold(0, (s, r) => s + r.placesReservees);
  static int placesRestantes(CovoiturageTrajet trajet, Iterable<ReservationTrajet> reservations) => (trajet.places - placesConfirmees(reservations)).clamp(0, trajet.places).toInt();
  static bool peutReserver({required CovoiturageTrajet trajet, required String userId, required int places, required Iterable<ReservationTrajet> reservations}) => trajet.auteurId != userId && trajet.statut == StatutTrajetEnum.ouvert && places > 0 && places <= placesRestantes(trajet, reservations);
  static bool typeModifiable(CovoiturageTrajet original, TypeTrajetEnum nouveau) => original.type == nouveau;
  static bool peutAnnuler(CovoiturageTrajet trajet, DateTime maintenant) => maintenant.isBefore(trajet.departAt);
  static bool peutNotifier({required String destinataireId, required String auteurActionId}) => destinataireId != auteurActionId;
  static bool estDansZone(String? zoneUtilisateur, String zoneTrajet) => zoneUtilisateur?.trim().toLowerCase() == zoneTrajet.trim().toLowerCase();
  static bool peutEvaluer({required CovoiturageTrajet trajet, required String evaluateurId, required String evalueId, required Iterable<ReservationTrajet> reservations, required bool dejaEvalue}) {
    if (dejaEvalue || trajet.statut != StatutTrajetEnum.termine || evaluateurId == evalueId) return false;
    final participant = reservations.any((r) => r.participantId == evaluateurId && r.statut == StatutReservationEnum.confirmee);
    final cibleParticipant = reservations.any((r) => r.participantId == evalueId && r.statut == StatutReservationEnum.confirmee);
    return (evaluateurId == trajet.auteurId && cibleParticipant) || (participant && evalueId == trajet.auteurId);
  }
  static StatutTrajetEnum statutApresReservations(CovoiturageTrajet trajet, Iterable<ReservationTrajet> reservations) => placesConfirmees(reservations) >= trajet.places ? StatutTrajetEnum.complet : StatutTrajetEnum.ouvert;
  static List<ReservationTrajet> refusAutomatiqueAutres(String confirmeeId, Iterable<ReservationTrajet> reservations) => [for (final r in reservations) if (r.id != confirmeeId && r.statut == StatutReservationEnum.enAttente) r.copyWith(statut: StatutReservationEnum.refusee)];
}
