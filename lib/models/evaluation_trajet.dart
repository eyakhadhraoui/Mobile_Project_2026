class EvaluationTrajet {
  const EvaluationTrajet({required this.id, required this.trajetId, required this.evaluateurId, required this.evalueId, required this.note, this.commentaire = '', required this.dateCreation});
  final String id, trajetId, evaluateurId, evalueId, commentaire, dateCreation;
  final int note;
  Map<String, Object?> toMap() => {'id': id, 'trajetId': trajetId, 'evaluateurId': evaluateurId, 'evalueId': evalueId, 'note': note, 'commentaire': commentaire, 'dateCreation': dateCreation};
  factory EvaluationTrajet.fromMap(Map<String, Object?> m) => EvaluationTrajet(id: m['id']! as String, trajetId: m['trajetId']! as String, evaluateurId: m['evaluateurId']! as String, evalueId: m['evalueId']! as String, note: m['note']! as int, commentaire: m['commentaire'] as String? ?? '', dateCreation: m['dateCreation']! as String);
}
