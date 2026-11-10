enum StatutMaintenance { enAttente, enCours, terminee }

extension StatutMaintenanceLabel on StatutMaintenance {
  String get label => switch (this) {
    StatutMaintenance.enAttente => 'En attente',
    StatutMaintenance.enCours => 'En cours',
    StatutMaintenance.terminee => 'Terminée',
  };
}

StatutMaintenance statutDepuisNom(Object? nom) =>
    StatutMaintenance.values.firstWhere(
      (statut) => statut.name == nom,
      orElse: () => StatutMaintenance.enAttente,
    );

const Object _unchanged = Object();

class DemandeMaintenance {
  const DemandeMaintenance({
    required this.id,
    required this.userId,
    this.assigneeId,
    this.assigneeNom,
    this.logementId,
    this.logementTitre,
    this.proprietaireId,
    this.proprietaireNom,
    required this.category,
    required this.room,
    required this.urgency,
    required this.title,
    required this.description,
    required this.residentName,
    required this.residentPhone,
    this.photoPath,
    this.statut = StatutMaintenance.enAttente,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String? assigneeId;

  /// « prenom nom » du prestataire : lu en base, jamais écrit.
  final String? assigneeNom;

  /// Annonce du logement loué concerné par la demande.
  final String? logementId;
  final String? logementTitre;
  final String? proprietaireId;
  final String? proprietaireNom;
  final String category;
  final String room;
  final String urgency;
  final String title;
  final String description;
  final String residentName;
  final String residentPhone;
  final String? photoPath;
  final StatutMaintenance statut;
  final DateTime createdAt;

  /// [photoPath] et [assigneeId] : null retire la valeur, ne rien passer la conserve.
  DemandeMaintenance copyWith({
    String? id,
    String? userId,
    Object? assigneeId = _unchanged,
    String? logementId,
    String? logementTitre,
    String? proprietaireId,
    String? proprietaireNom,
    String? category,
    String? room,
    String? urgency,
    String? title,
    String? description,
    String? residentName,
    String? residentPhone,
    Object? photoPath = _unchanged,
    StatutMaintenance? statut,
    DateTime? createdAt,
  }) {
    final memeAssigne = identical(assigneeId, _unchanged);
    return DemandeMaintenance(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      assigneeId: memeAssigne ? this.assigneeId : assigneeId as String?,
      assigneeNom: memeAssigne ? assigneeNom : null,
      logementId: logementId ?? this.logementId,
      logementTitre: logementTitre ?? this.logementTitre,
      proprietaireId: proprietaireId ?? this.proprietaireId,
      proprietaireNom: proprietaireNom ?? this.proprietaireNom,
      category: category ?? this.category,
      room: room ?? this.room,
      urgency: urgency ?? this.urgency,
      title: title ?? this.title,
      description: description ?? this.description,
      residentName: residentName ?? this.residentName,
      residentPhone: residentPhone ?? this.residentPhone,
      photoPath: identical(photoPath, _unchanged)
          ? this.photoPath
          : photoPath as String?,
      statut: statut ?? this.statut,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'assigneeId': assigneeId,
    'logementId': logementId,
    'logementTitre': logementTitre,
    'proprietaireId': proprietaireId,
    'proprietaireNom': proprietaireNom,
    'category': category,
    'room': room,
    'urgency': urgency,
    'title': title,
    'description': description,
    'residentName': residentName,
    'residentPhone': residentPhone,
    'photoPath': photoPath,
    'statut': statut.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DemandeMaintenance.fromJson(Map<String, dynamic> json) {
    return DemandeMaintenance(
      id: json['id'] as String,
      userId: json['userId'] as String,
      assigneeId: json['assigneeId'] as String?,
      assigneeNom: json['assigneeNom'] as String?,
      logementId: json['logementId'] as String?,
      logementTitre: json['logementTitre'] as String?,
      proprietaireId: json['proprietaireId'] as String?,
      proprietaireNom: json['proprietaireNom'] as String?,
      category: json['category'] as String,
      room: json['room'] as String,
      urgency: json['urgency'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      residentName: json['residentName'] as String,
      residentPhone: json['residentPhone'] as String,
      photoPath: json['photoPath'] as String?,
      statut: statutDepuisNom(json['statut']),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class DemandeHistorique {
  const DemandeHistorique({
    required this.statut,
    required this.date,
    this.auteurId,
  });

  final StatutMaintenance statut;
  final DateTime date;
  final String? auteurId;

  factory DemandeHistorique.fromJson(Map<String, Object?> json) =>
      DemandeHistorique(
        statut: statutDepuisNom(json['statut']),
        date: DateTime.parse(json['date']! as String),
        auteurId: json['auteurId'] as String?,
      );
}
