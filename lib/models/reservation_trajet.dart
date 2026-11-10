import 'enums_covoiturage.dart';
class ReservationTrajet {
  const ReservationTrajet({required this.id, required this.trajetId, required this.participantId, required this.participantNom, required this.placesReservees, required this.dateCreation, this.statut = StatutReservationEnum.enAttente});
  final String id, trajetId, participantId, participantNom, dateCreation;
  final int placesReservees;
  final StatutReservationEnum statut;
  Map<String, Object?> toMap() => {'id': id, 'trajetId': trajetId, 'participantId': participantId, 'participantNom': participantNom, 'placesReservees': placesReservees, 'dateCreation': dateCreation, 'statut': statut.name};
  factory ReservationTrajet.fromMap(Map<String, Object?> m) => ReservationTrajet(id: m['id']! as String, trajetId: m['trajetId']! as String, participantId: m['participantId']! as String, participantNom: m['participantNom']! as String, placesReservees: m['placesReservees']! as int, dateCreation: m['dateCreation']! as String, statut: StatutReservationEnum.values.byName(m['statut'] as String? ?? 'enAttente'));
  ReservationTrajet copyWith({StatutReservationEnum? statut}) => ReservationTrajet(id: id, trajetId: trajetId, participantId: participantId, participantNom: participantNom, placesReservees: placesReservees, dateCreation: dateCreation, statut: statut ?? this.statut);
}
