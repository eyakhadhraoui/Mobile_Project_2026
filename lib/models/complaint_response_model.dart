import 'complaint_model.dart';

/// Auteur d'un message dans les échanges d'une réclamation.
enum ComplaintAuthorRole { proprietaire, etudiant }

/// Message d'une réclamation : réponse du propriétaire ou message de l'étudiant.
class ComplaintResponse {
  const ComplaintResponse({
    required this.id,
    required this.complaintId,
    required this.authorId,
    required this.authorRole,
    required this.text,
    required this.createdAt,
    this.langue = 'fr',
    this.updatedAt,
    this.syncStatus = ComplaintSyncStatus.pending,
    this.isDeleted = false,
  });

  final String id;
  final String complaintId;
  final String authorId;
  final ComplaintAuthorRole authorRole;
  final String text;

  /// Langue dans laquelle l'auteur a écrit (sa langue de profil au moment de l'envoi).
  final String langue;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final ComplaintSyncStatus syncStatus;
  final bool isDeleted;

  bool get estDuProprietaire => authorRole == ComplaintAuthorRole.proprietaire;

  ComplaintResponse copyWith({String? text, DateTime? updatedAt, ComplaintSyncStatus? syncStatus, bool? isDeleted}) =>
      ComplaintResponse(
        id: id,
        complaintId: complaintId,
        authorId: authorId,
        authorRole: authorRole,
        text: text ?? this.text,
        langue: langue,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        isDeleted: isDeleted ?? this.isDeleted,
      );
}
