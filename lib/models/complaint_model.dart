enum ComplaintCategory {
  bruit,
  panne,
  loyer,
  voisinage,
  autre,
  fuiteEau,
  electricite,
  chauffage,
  equipement,
  proprietaire,
}

enum ComplaintStatus { ouverte, enCours, cloturee }
enum ComplaintPriority { faible, moyenne, urgente }

class ComplaintHistoryEntry {
  const ComplaintHistoryEntry({required this.status, required this.date});

  final ComplaintStatus status;
  final DateTime date;
}

class ComplaintModel {
  const ComplaintModel({
    required this.id,
    required this.userId,
    required this.locationId,
    required this.subject,
    required this.category,
    required this.description,
    required this.photos,
    required this.status,
    required this.createdAt,
    this.priority = ComplaintPriority.moyenne,
    this.history = const [],
  });

  final String id;
  final String userId;
  final String locationId;
  final String subject;
  final ComplaintCategory category;
  final String description;
  final List<String> photos;
  final ComplaintStatus status;
  final DateTime createdAt;
  final ComplaintPriority priority;
  final List<ComplaintHistoryEntry> history;
}
