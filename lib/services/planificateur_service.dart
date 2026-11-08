import '../models/annonce.dart';
import 'annonce_cache_service.dart';
import 'heure_service.dart';

/// Publie localement les annonces programmées arrivées à échéance.
///
/// Le serveur fait la même opération de son côté (c'est lui qui rend
/// l'annonce visible aux autres utilisateurs) ; le planificateur local met à
/// jour la base SQLite pour que l'application reste juste hors ligne, et
/// rattrape les publications manquées quand le téléphone était éteint.
class PlanificateurService {
  PlanificateurService({AnnonceCacheService? cache, HeureService? heure})
    : _cache = cache ?? AnnonceCacheService(),
      _heure = heure ?? HeureService();

  final AnnonceCacheService _cache;
  final HeureService _heure;

  /// Passe à [statutCible] (publiee par défaut ; enAttente si la modération
  /// l'exige) les annonces « programmee » de [userId] dont la date est passée,
  /// selon l'heure officielle ou, à défaut, l'horloge du téléphone.
  /// Retourne les annonces modifiées.
  Future<List<Annonce>> publierAnnoncesEchues({
    required String userId,
    StatutAnnonce Function(Annonce annonce)? statutCible,
  }) async {
    // Aucune annonce programmée : inutile d'interroger l'API d'heure.
    if (!await _cache.aDesProgrammees(userId)) return const [];
    final maintenant = await _heure.heureActuelle();
    final echues = await _cache.programmeesEchues(userId, maintenant);
    final publiees = <Annonce>[];
    for (final annonce in echues) {
      final statut = statutCible?.call(annonce) ?? StatutAnnonce.publiee;
      await _cache.changerStatut(annonce.id, statut);
      publiees.add(annonce.copyWith(statut: statut));
    }
    return publiees;
  }
}
