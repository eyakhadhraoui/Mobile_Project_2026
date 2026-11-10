/// Libellés des valeurs renvoyées par le serveur.
const categoriesAssistant = {
  'plomberie': 'Plomberie et fuite d’eau',
  'electricite': 'Panne électrique',
  'chauffage_climatisation': 'Chauffage et climatisation',
  'retard_loyer': 'Retard de loyer',
  'voisinage': 'Voisinage et bruit',
  'degradations': 'Dégradations',
  'contrat': 'Contrat de location',
  'retard_reparations': 'Retard de réparations',
  'caution': 'Caution et remboursement',
  'photos_annonce': 'Photos d’annonce contestées',
  'entretien': 'Entretien du logement',
  'autre': 'Autre',
};

const urgencesAssistant = {
  'faible': 'Urgence faible',
  'moyen': 'Urgence moyenne',
  'eleve': 'Urgence élevée',
};

const statutsAssistant = {
  'ouverte': 'Ouverte',
  'en_cours': 'En cours',
  'resolue': 'Résolue',
};

const personnesAssistant = {
  'locataire': 'Le locataire',
  'proprietaire': 'Le propriétaire',
  'voisin': 'Un voisin',
  'prestataire': 'Un prestataire',
  'autre': 'Autre personne',
  'indetermine': 'Non précisée',
};

String nomRoleAssistant(String role) =>
    role == 'proprietaire' ? 'Propriétaire' : 'Locataire';

/// Vrai si le texte est majoritairement écrit en arabe.
bool estTexteArabe(String texte) {
  final lettres = texte.replaceAll(RegExp(r'\s'), '').length;
  return lettres > 0 &&
      RegExp(r'[ء-ي]').allMatches(texte).length > lettres / 3;
}

class AnalyseReclamation {
  const AnalyseReclamation({
    required this.categorie,
    required this.urgence,
    required this.personneConcernee,
    this.informations = const [],
    this.questions = const [],
    this.avisProfessionnel = false,
  });

  final String categorie;
  final String urgence;
  final String personneConcernee;
  final List<({String champ, String valeur})> informations;
  final List<String> questions;
  final bool avisProfessionnel;

  factory AnalyseReclamation.fromJson(Map<dynamic, dynamic> json) => AnalyseReclamation(
    categorie: json['categorie'] as String? ?? 'autre',
    urgence: json['urgence'] as String? ?? 'moyen',
    personneConcernee: json['personneConcernee'] as String? ?? 'indetermine',
    informations: [
      for (final item in (json['informations'] as List? ?? const []).whereType<Map>())
        (champ: item['champ'] as String? ?? '', valeur: item['valeur'] as String? ?? ''),
    ],
    questions: (json['questions'] as List? ?? const []).whereType<String>().toList(),
    avisProfessionnel: json['avisProfessionnel'] == true,
  );
}

class MessageAssistant {
  const MessageAssistant({
    required this.deUtilisateur,
    required this.texte,
    this.date,
    this.analyse,
    this.sources = const [],
  });

  final bool deUtilisateur;
  final String texte;
  final DateTime? date;
  final AnalyseReclamation? analyse;

  /// Titres des guides utilisés pour répondre.
  final List<String> sources;

  factory MessageAssistant.fromJson(Map<dynamic, dynamic> json) {
    final analyse = json['analyse'];
    return MessageAssistant(
      deUtilisateur: json['auteur'] == 'utilisateur',
      texte: json['texte'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '')?.toLocal(),
      analyse: analyse is Map ? AnalyseReclamation.fromJson(analyse) : null,
      sources: [
        for (final source in (json['sources'] as List? ?? const []).whereType<Map>())
          source['titre'] as String? ?? '',
      ],
    );
  }
}

class ConversationReclamation {
  const ConversationReclamation({
    required this.id,
    required this.role,
    required this.titre,
    required this.categorie,
    required this.urgence,
    required this.statut,
    this.miseAJour,
    this.nombreMessages = 0,
    this.messages = const [],
  });

  final String id;
  final String role;
  final String titre;
  final String categorie;
  final String urgence;
  final String statut;
  final DateTime? miseAJour;
  final int nombreMessages;
  final List<MessageAssistant> messages;

  factory ConversationReclamation.fromJson(Map<dynamic, dynamic> json) {
    final messages = [
      for (final item in (json['messages'] as List? ?? const []).whereType<Map>())
        MessageAssistant.fromJson(item),
    ];
    return ConversationReclamation(
      id: json['id'] as String,
      role: json['role'] as String? ?? 'locataire',
      titre: json['titre'] as String? ?? 'Réclamation',
      categorie: json['categorie'] as String? ?? 'autre',
      urgence: json['urgence'] as String? ?? 'moyen',
      statut: json['statut'] as String? ?? 'ouverte',
      miseAJour: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toLocal(),
      nombreMessages: (json['nombreMessages'] as num?)?.toInt() ?? messages.length,
      messages: messages,
    );
  }
}
