import 'enums_covoiturage.dart';
class NotificationCovoiturage {
  const NotificationCovoiturage({required this.id, required this.userId, required this.type, required this.titre, required this.message, this.trajetId, this.reservationId, this.lue = false, required this.dateCreation, this.cleUnique});
  final String id, userId, titre, message, dateCreation;
  final TypeNotificationEnum type;
  final String? trajetId, reservationId, cleUnique;
  final bool lue;
  Map<String, Object?> toMap() => {'id': id, 'userId': userId, 'type': type.name, 'titre': titre, 'message': message, 'trajetId': trajetId, 'reservationId': reservationId, 'lue': lue ? 1 : 0, 'dateCreation': dateCreation, 'cleUnique': cleUnique};
  factory NotificationCovoiturage.fromMap(Map<String, Object?> m) => NotificationCovoiturage(id: m['id']! as String, userId: m['userId']! as String, type: TypeNotificationEnum.values.byName(m['type']! as String), titre: m['titre']! as String, message: m['message']! as String, trajetId: m['trajetId'] as String?, reservationId: m['reservationId'] as String?, lue: (m['lue'] as int? ?? 0) == 1, dateCreation: m['dateCreation']! as String, cleUnique: m['cleUnique'] as String?);
}
