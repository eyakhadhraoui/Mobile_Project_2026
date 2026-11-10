import '../core/constants/langues.dart';

enum EtatEnvoi { envoye, enAttente, echec }

DateTime _date(Object? valeur) =>
    DateTime.tryParse(valeur as String? ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Langue d'un message : l'écriture du texte prime sur la langue du profil, car
/// un compte réglé en français peut très bien écrire en arabe, et inversement.
String langueDuTexte(String texte, String langueProfil) {
  if (RegExp(r'[؀-ۿ]').hasMatch(texte)) return 'ar';
  if (RegExp(r'[Ѐ-ӿ]').hasMatch(texte)) return 'ru';
  final profil = langueValide(langueProfil);
  return profil == 'ar' || profil == 'ru' ? langueParDefaut : profil;
}

class MessageDiscussion {
  const MessageDiscussion({
    required this.id,
    required this.auteurId,
    required this.texte,
    required this.photos,
    required this.langue,
    required this.date,
    this.clientId,
    this.etat = EtatEnvoi.envoye,
    this.erreur,
  });

  factory MessageDiscussion.fromJson(Map<String, dynamic> json) => MessageDiscussion(
    id: json['id'] as String,
    auteurId: json['auteurId'] as String,
    texte: json['texte'] as String? ?? '',
    photos: [for (final photo in json['photos'] as List? ?? const []) photo as String],
    langue: langueValide(json['langue']),
    date: _date(json['createdAt']),
    clientId: json['clientId'] as String?,
  );

  final String id;
  final String auteurId;
  final String texte;

  /// Chemins serveur (`/photos/...`), ou fichiers locaux tant que le message attend.
  final List<String> photos;
  final String langue;
  final DateTime date;
  final String? clientId;
  final EtatEnvoi etat;
  final String? erreur;
}

class ConversationResume {
  const ConversationResume({
    required this.id,
    required this.annonceId,
    required this.annonceTitre,
    required this.interlocuteurNom,
    required this.estProprietaire,
    required this.nonLus,
    required this.date,
    this.annoncePhoto,
    this.dernierTexte = '',
    this.dernierNbPhotos = 0,
    this.dernierAuteurId,
  });

  factory ConversationResume.fromJson(Map<String, dynamic> json) {
    final dernier = json['dernierMessage'] as Map?;
    return ConversationResume(
      id: json['id'] as String,
      annonceId: json['annonceId'] as String,
      annonceTitre: json['annonceTitre'] as String? ?? 'Annonce',
      interlocuteurNom: json['interlocuteurNom'] as String? ?? 'Utilisateur',
      estProprietaire: json['estProprietaire'] == true,
      nonLus: (json['nonLus'] as num?)?.toInt() ?? 0,
      date: _date(dernier?['createdAt'] ?? json['updatedAt']),
      annoncePhoto: json['annoncePhoto'] as String?,
      dernierTexte: dernier?['texte'] as String? ?? '',
      dernierNbPhotos: (dernier?['nbPhotos'] as num?)?.toInt() ?? 0,
      dernierAuteurId: dernier?['auteurId'] as String?,
    );
  }

  final String id;
  final String annonceId;
  final String annonceTitre;
  final String? annoncePhoto;
  final String interlocuteurNom;
  final bool estProprietaire;
  final int nonLus;
  final DateTime date;
  final String dernierTexte;
  final int dernierNbPhotos;
  final String? dernierAuteurId;

  /// Dernier message tel qu'affiché dans la liste, vu par [lecteurId].
  String apercu(String lecteurId) {
    final contenu = dernierTexte.isNotEmpty
        ? dernierTexte
        : dernierNbPhotos > 1
        ? '$dernierNbPhotos photos'
        : 'Photo';
    return dernierAuteurId == lecteurId ? 'Vous : $contenu' : contenu;
  }
}

/// Messages d'une conversation, avec l'ETag servant au suivi des nouveautés.
class PageMessages {
  const PageMessages(this.messages, this.etag);
  final List<MessageDiscussion> messages;
  final String? etag;
}
