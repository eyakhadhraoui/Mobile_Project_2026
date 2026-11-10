import '../models/conversation_reclamation.dart';
import 'api_client.dart';

/// Conversations de l'assistant. Flutter ne parle qu'au serveur StudentHub :
/// seul le serveur appelle le modèle d'IA.
class AssistantReclamationService {
  AssistantReclamationService({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;
  static const _base = '/assistant/conversations';

  ConversationReclamation _conversation(dynamic data) =>
      ConversationReclamation.fromJson(data as Map);

  /// Rôle de l'utilisateur et historique (lisible sans connexion).
  Future<({String role, List<ConversationReclamation> conversations})> lister() async {
    final data = await _api.getAvecCache(_base) as Map;
    return (
      role: data['role'] as String? ?? 'locataire',
      conversations: [
        for (final item in (data['conversations'] as List? ?? const []).whereType<Map>())
          ConversationReclamation.fromJson(item),
      ],
    );
  }

  Future<ConversationReclamation> detail(String id) async =>
      _conversation(await _api.getAvecCache('$_base/$id'));

  Future<ConversationReclamation> creer(String message) async =>
      _conversation(await _api.post(_base, {'message': message}));

  Future<ConversationReclamation> envoyer(String id, String message) async =>
      _conversation(await _api.post('$_base/$id/messages', {'message': message}));

  Future<ConversationReclamation> changerStatut(String id, String statut) async =>
      _conversation(await _api.post('$_base/$id/statut', {'statut': statut}));

  Future<void> supprimer(String id) => _api.delete('$_base/$id');
}
