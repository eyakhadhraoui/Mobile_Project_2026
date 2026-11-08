import '../../models/complaint_model.dart';
import 'texte.dart';

/// Types de danger reconnus dans une description de réclamation.
enum TypeDanger { gaz, electrique, incendie, inondation, structure }

/// Danger détecté localement (sans réseau) : la réclamation passe en urgente.
class DangerDetecte {
  const DangerDetecte({required this.type, required this.motCle});
  final TypeDanger type;

  /// Expression trouvée dans le texte (pour expliquer la détection).
  final String motCle;

  String get libelle => switch (type) {
    TypeDanger.gaz => 'Risque lié au gaz',
    TypeDanger.electrique => 'Risque électrique',
    TypeDanger.incendie => 'Risque d’incendie',
    TypeDanger.inondation => 'Inondation',
    TypeDanger.structure => 'Risque d’effondrement',
  };

  /// Consignes de sécurité affichées immédiatement à l'étudiant.
  List<String> get consignes => consignesSecurite[type]!;

  /// Catégorie évidente pour ce danger (null : laissée au choix de l'étudiant ou de l'IA).
  ComplaintCategory? get categorie => switch (type) {
    TypeDanger.electrique => ComplaintCategory.electricite,
    TypeDanger.inondation => ComplaintCategory.fuiteEau,
    _ => null,
  };
}

/// Numéros d'urgence en Tunisie : Protection civile 198, SAMU 190, Police 197.
const consignesSecurite = <TypeDanger, List<String>>{
  TypeDanger.gaz: [
    'N’allumez ni flamme ni interrupteur, ne branchez rien.',
    'Ouvrez les fenêtres et fermez le robinet de gaz si c’est possible.',
    'Sortez du logement et prévenez les voisins.',
    'Appelez la Protection civile (198) depuis l’extérieur.',
  ],
  TypeDanger.electrique: [
    'Ne touchez ni aux fils, ni à la prise, ni à l’appareil.',
    'Coupez le disjoncteur général si vous pouvez le faire sans risque.',
    'Éloignez-vous de toute zone humide.',
    'En cas de feu ou de blessure : Protection civile (198), SAMU (190).',
  ],
  TypeDanger.incendie: [
    'Sortez immédiatement et fermez la porte derrière vous.',
    'N’utilisez pas l’ascenseur.',
    'Appelez la Protection civile (198).',
  ],
  TypeDanger.inondation: [
    'Ne touchez pas aux appareils électriques mouillés.',
    'Coupez l’électricité de la zone si possible, sans marcher dans l’eau.',
    'Fermez le robinet d’arrivée d’eau.',
    'Mettez vos affaires et papiers en hauteur.',
  ],
  TypeDanger.structure: [
    'Éloignez-vous de la zone endommagée (plafond, mur, balcon).',
    'Ne restez pas dessous et empêchez l’accès.',
    'En cas de danger immédiat : Protection civile (198).',
  ],
};

/// Expressions (texte normalisé, sans accents) associées à chaque danger.
final _motifs = <TypeDanger, RegExp>{
  TypeDanger.gaz: RegExp(r'\b(gaz|monoxyde)\b'),
  TypeDanger.electrique: RegExp(
    r'\b(etincelles?|court circuits?|cables? denudes?|fils? denudes?|electrocut\w*|prise qui (chauffe|fond)|ca grille)\b',
  ),
  TypeDanger.incendie: RegExp(r'\b(incendie|feu|flammes?|fumee|odeur de brule)\b'),
  TypeDanger.inondation: RegExp(r'\b(inond\w*|deborde\w*|eau partout|degats? des eaux)\b'),
  TypeDanger.structure: RegExp(r'\b(effondr\w*|plafond (qui )?tombe\w*|menace de tomber)\b'),
};

/// Dangers présents dans [texte], du plus grave au moins grave (ordre de l'enum).
List<DangerDetecte> detecterDangers(String texte) {
  final normalise = normaliserTexte(texte);
  return [
    for (final entree in _motifs.entries)
      if (entree.value.firstMatch(normalise) case final match?)
        DangerDetecte(type: entree.key, motCle: match.group(0)!),
  ];
}
