class PhotoAnalysis {
  const PhotoAnalysis({
    required this.isMaintenanceIssue,
    this.category,
    this.room,
    this.urgency,
    this.title,
    this.description,
  });

  final bool isMaintenanceIssue;
  final String? category;
  final String? room;
  final String? urgency;
  final String? title;
  final String? description;

  factory PhotoAnalysis.fromJson(Map<String, dynamic> json) {
    String? texte(String cle) {
      final valeur = json[cle];
      return valeur is String ? valeur : null;
    }

    return PhotoAnalysis(
      isMaintenanceIssue: json['is_maintenance_issue'] == true,
      category: texte('category'),
      room: texte('room'),
      urgency: texte('urgency'),
      title: texte('title'),
      description: texte('description'),
    );
  }
}
