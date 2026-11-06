import 'api_client.dart';

class CreneauVisite {
  const CreneauVisite({required this.debut, required this.fin, required this.startAt});
  final DateTime debut;
  final DateTime fin;

  /// Valeur exacte renvoyée au serveur pour réserver (AAAA-MM-JJTHH:MM).
  final String startAt;
}

/// Visite ou demande de location, vue par le propriétaire ou par le client.
class DemandeLogement {
  const DemandeLogement(this.data);
  final Map<String, dynamic> data;

  String get id => data['id'] as String;
  String get statut => data['status'] as String? ?? '';
  String get annonceTitre => data['annonceTitre'] as String? ?? 'Annonce';
  String get clientNom => data['clientNom'] as String? ?? 'Utilisateur';
  String get proprietaireNom => data['proprietaireNom'] as String? ?? 'Utilisateur';
  DateTime? date(String key) => DateTime.tryParse(data[key] as String? ?? '');
}

class ActiviteAnnonce {
  const ActiviteAnnonce(this.data);
  final Map<String, dynamic> data;

  String get type => data['type'] as String? ?? '';
  String get annonceTitre => data['annonceTitre'] as String? ?? '';
  String get auteur => data['auteur'] as String? ?? 'Utilisateur';
  String get detail => data['detail'] as String? ?? '';
  DateTime? get date => DateTime.tryParse(data['date'] as String? ?? '')?.toLocal();
}

class HousingService {
  HousingService({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  Future<List<CreneauVisite>> creneaux(String annonceId) async {
    final data = await _api.get('/annonces/$annonceId/creneaux') as List;
    return data.map((item) {
      final slot = Map<String, dynamic>.from(item as Map);
      return CreneauVisite(
        debut: DateTime.parse(slot['startAt'] as String),
        fin: DateTime.parse(slot['endAt'] as String),
        startAt: slot['startAt'] as String,
      );
    }).toList();
  }

  Future<void> reserverVisite(String annonceId, String startAt) =>
      _api.post('/visites', {'annonceId': annonceId, 'startAt': startAt});

  Future<void> annulerVisite(String id) => _api.post('/visites/$id/statut', {'statut': 'cancelled'});

  Future<({List<DemandeLogement> recues, List<DemandeLogement> envoyees})> visites() => _paire('/visites');

  Future<List<Map<String, dynamic>>> disponibilites() async =>
      (await _api.get('/disponibilites') as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();

  Future<void> ajouterDisponibilite(Map<String, dynamic> disponibilite) => _api.post('/disponibilites', disponibilite);

  Future<void> supprimerDisponibilite(String id) => _api.delete('/disponibilites/$id');

  Future<void> demanderLocation(Map<String, dynamic> demande) => _api.post('/demandes-location', demande);

  Future<({List<DemandeLogement> recues, List<DemandeLogement> envoyees})> demandesLocation() =>
      _paire('/demandes-location');

  /// [statut] : accepted / refused (propriétaire) ou cancelled (demandeur).
  Future<void> repondreDemande(String id, String statut) =>
      _api.post('/demandes-location/$id/statut', {'statut': statut});

  Future<List<ActiviteAnnonce>> activite() async => (await _api.get('/activite') as List)
      .map((item) => ActiviteAnnonce(Map<String, dynamic>.from(item as Map)))
      .toList();

  Future<({List<DemandeLogement> recues, List<DemandeLogement> envoyees})> _paire(String path) async {
    final data = Map<String, dynamic>.from(await _api.get(path) as Map);
    List<DemandeLogement> list(String key) => (data[key] as List? ?? const [])
        .map((item) => DemandeLogement(Map<String, dynamic>.from(item as Map)))
        .toList();
    return (recues: list('recues'), envoyees: list('envoyees'));
  }
}
