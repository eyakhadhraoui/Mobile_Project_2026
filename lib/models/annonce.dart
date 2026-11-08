/// Statuts d'une annonce, stockés par leur nom (`statut.name`) en base et sur le serveur.
enum StatutAnnonce { enAttente, publiee, archivee, programmee }

extension StatutAnnonceLabel on StatutAnnonce {
  String get libelle => switch (this) {
    StatutAnnonce.enAttente => 'En attente de validation',
    StatutAnnonce.publiee => 'Publiée',
    StatutAnnonce.archivee => 'Archivée',
    StatutAnnonce.programmee => 'Programmée',
  };

  /// Lit un statut stocké par son nom (valeur par défaut : en attente).
  static StatutAnnonce depuisNom(Object? nom) => StatutAnnonce.values.firstWhere(
    (value) => value.name == nom,
    orElse: () => StatutAnnonce.enAttente,
  );
}

/// Date ISO 8601 en UTC, à la seconde près (ex. 2026-11-05T13:00:00.000Z).
/// Le format est toujours le même, donc deux dates se comparent comme des chaînes
/// (utile pour les requêtes SQLite).
String isoUtc(DateTime date) {
  final u = date.toUtc();
  return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second).toIso8601String();
}

/// Date lue depuis une chaîne ISO 8601, ramenée en UTC (null si absente ou invalide).
DateTime? lireDateUtc(Object? valeur) => valeur is String ? DateTime.tryParse(valeur)?.toUtc() : null;

String _deux(int v) => v.toString().padLeft(2, '0');

/// « JJ/MM/AAAA à HH:mm » dans le fuseau du téléphone.
String formatDateHeure(DateTime date) {
  final d = date.toLocal();
  return '${_deux(d.day)}/${_deux(d.month)}/${d.year} à ${_deux(d.hour)}:${_deux(d.minute)}';
}

class Annonce {
  const Annonce({
    required this.id,
    required this.categorie,
    required this.titre,
    required this.description,
    this.typeLocation = '',
    this.loyer = 0,
    this.surface = 0,
    this.chambres = 0,
    this.etage,
    this.ville = '',
    this.quartier = '',
    this.adresse = '',
    this.photos = const [],
    this.statut = StatutAnnonce.enAttente,
    this.motifModeration = '',
    required this.proprietaireId,
    this.proprietaireNom = '',
    this.autoriserCommentaires = true,
    this.createdAt,
    this.datePublication,
    this.likes = 0,
    this.aimeParMoi = false,
    this.nbCommentaires = 0,
    this.noteMoyenne = 0,
    this.nbAvis = 0,
    this.maNote,
  });

  static const categories = ['Logement', 'Résidence', 'Événement', 'Avis', 'Autre'];
  static const typesLogement = ['Studio', 'Chambre', 'Colocation', 'Appartement', 'Maison'];

  final String id;

  /// Logement, Résidence, Événement, Avis ou Autre.
  final String categorie;
  final String titre;
  final String description;

  /// Champs propres à la catégorie Logement (vides sinon).
  final String typeLocation;
  final double loyer;
  final double surface;
  final int chambres;
  final int? etage;
  final String ville;
  final String quartier;
  final String adresse;

  /// Chemins serveur (`/photos/...`) ou, avant envoi, chemins de fichiers locaux.
  final List<String> photos;
  final StatutAnnonce statut;
  final String motifModeration;
  final String proprietaireId;
  final String proprietaireNom;
  final bool autoriserCommentaires;
  final DateTime? createdAt;

  /// Date (UTC) de publication programmée. Pour une annonce publiée après
  /// programmation, elle est conservée comme date de publication réelle.
  final DateTime? datePublication;

  /// Statistiques calculées par le serveur pour l'utilisateur connecté.
  final int likes;
  final bool aimeParMoi;
  final int nbCommentaires;
  final double noteMoyenne;
  final int nbAvis;
  final int? maNote;

  bool get estLogement => categorie == 'Logement';
  bool get estPubliee => statut == StatutAnnonce.publiee;
  bool get estProgrammee => statut == StatutAnnonce.programmee;

  /// Vraie si la publication programmée est arrivée à échéance à [maintenant].
  bool estEchue(DateTime maintenant) =>
      estProgrammee && datePublication != null && !datePublication!.isAfter(maintenant);

  /// Badge affiché dans « Mes annonces » : « Programmée le JJ/MM/AAAA à HH:mm ».
  String? get libelleProgrammation =>
      estProgrammee && datePublication != null ? 'Programmée le ${formatDateHeure(datePublication!)}' : null;

  /// Date affichée dans l'en-tête : la publication réelle si elle a été programmée.
  DateTime? get dateAffichee => estPubliee && datePublication != null ? datePublication!.toLocal() : createdAt;

  Annonce copyWith({
    String? categorie,
    String? titre,
    String? description,
    String? typeLocation,
    double? loyer,
    double? surface,
    int? chambres,
    Object? etage = _unchanged,
    String? ville,
    String? quartier,
    String? adresse,
    List<String>? photos,
    StatutAnnonce? statut,
    Object? datePublication = _unchanged,
    bool? autoriserCommentaires,
    int? likes,
    bool? aimeParMoi,
  }) => Annonce(
    id: id,
    categorie: categorie ?? this.categorie,
    titre: titre ?? this.titre,
    description: description ?? this.description,
    typeLocation: typeLocation ?? this.typeLocation,
    loyer: loyer ?? this.loyer,
    surface: surface ?? this.surface,
    chambres: chambres ?? this.chambres,
    etage: identical(etage, _unchanged) ? this.etage : etage as int?,
    ville: ville ?? this.ville,
    quartier: quartier ?? this.quartier,
    adresse: adresse ?? this.adresse,
    photos: photos ?? this.photos,
    statut: statut ?? this.statut,
    motifModeration: motifModeration,
    proprietaireId: proprietaireId,
    proprietaireNom: proprietaireNom,
    autoriserCommentaires: autoriserCommentaires ?? this.autoriserCommentaires,
    createdAt: createdAt,
    datePublication: identical(datePublication, _unchanged) ? this.datePublication : datePublication as DateTime?,
    likes: likes ?? this.likes,
    aimeParMoi: aimeParMoi ?? this.aimeParMoi,
    nbCommentaires: nbCommentaires,
    noteMoyenne: noteMoyenne,
    nbAvis: nbAvis,
    maNote: maNote,
  );

  /// Données envoyées au serveur lors d'une création ou d'une modification.
  Map<String, dynamic> toPayload() => {
    'categorie': categorie,
    'titre': titre,
    'description': description,
    'photos': photos,
    'autoriserCommentaires': autoriserCommentaires,
    // null : publication immédiate (ou annulation d'une programmation).
    'datePublication': datePublication == null ? null : isoUtc(datePublication!),
    if (estLogement) ...{
      'typeLocation': typeLocation,
      'loyer': loyer,
      'surface': surface,
      'chambres': chambres,
      'etage': etage,
      'ville': ville,
      'quartier': quartier,
      'adresse': adresse,
    },
  };

  factory Annonce.fromJson(Map<String, dynamic> json) => Annonce(
    id: json['id'] as String,
    categorie: json['categorie'] as String? ?? 'Autre',
    titre: json['titre'] as String? ?? '',
    description: json['description'] as String? ?? '',
    typeLocation: json['typeLocation'] as String? ?? '',
    loyer: (json['loyer'] as num? ?? 0).toDouble(),
    surface: (json['surface'] as num? ?? 0).toDouble(),
    chambres: (json['chambres'] as num? ?? 0).toInt(),
    etage: (json['etage'] as num?)?.toInt(),
    ville: json['ville'] as String? ?? '',
    quartier: json['quartier'] as String? ?? '',
    adresse: json['adresse'] as String? ?? '',
    photos: (json['photos'] as List? ?? const []).cast<String>(),
    statut: StatutAnnonceLabel.depuisNom(json['statut']),
    motifModeration: json['motifModeration'] as String? ?? '',
    proprietaireId: json['proprietaireId'] as String,
    proprietaireNom: json['proprietaireNom'] as String? ?? '',
    autoriserCommentaires: json['autoriserCommentaires'] as bool? ?? true,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal(),
    datePublication: lireDateUtc(json['datePublication']),
    likes: (json['likes'] as num? ?? 0).toInt(),
    aimeParMoi: json['aimeParMoi'] as bool? ?? false,
    nbCommentaires: (json['nbCommentaires'] as num? ?? 0).toInt(),
    noteMoyenne: (json['noteMoyenne'] as num? ?? 0).toDouble(),
    nbAvis: (json['nbAvis'] as num? ?? 0).toInt(),
    maNote: (json['maNote'] as num?)?.toInt(),
  );

  /// Copie complète (statistiques comprises) pour le cache SQLite hors ligne.
  /// Relue par [Annonce.fromJson].
  Map<String, dynamic> toJson() => {
    'id': id,
    'categorie': categorie,
    'titre': titre,
    'description': description,
    'typeLocation': typeLocation,
    'loyer': loyer,
    'surface': surface,
    'chambres': chambres,
    'etage': etage,
    'ville': ville,
    'quartier': quartier,
    'adresse': adresse,
    'photos': photos,
    'statut': statut.name,
    'motifModeration': motifModeration,
    'proprietaireId': proprietaireId,
    'proprietaireNom': proprietaireNom,
    'autoriserCommentaires': autoriserCommentaires,
    'createdAt': createdAt?.toUtc().toIso8601String(),
    'datePublication': datePublication == null ? null : isoUtc(datePublication!),
    'likes': likes,
    'aimeParMoi': aimeParMoi,
    'nbCommentaires': nbCommentaires,
    'noteMoyenne': noteMoyenne,
    'nbAvis': nbAvis,
    'maNote': maNote,
  };
}

class CommentaireAnnonce {
  const CommentaireAnnonce({required this.userId, required this.auteur, required this.texte, this.date});
  final String userId;
  final String auteur;
  final String texte;
  final DateTime? date;

  factory CommentaireAnnonce.fromJson(Map<String, dynamic> json) => CommentaireAnnonce(
    userId: json['userId'] as String? ?? '',
    auteur: json['author'] as String? ?? 'Utilisateur',
    texte: json['text'] as String? ?? '',
    date: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal(),
  );
}

const Object _unchanged = Object();
