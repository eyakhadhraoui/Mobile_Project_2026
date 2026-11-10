import 'package:flutter/foundation.dart';

import '../models/conversation_reclamation.dart';
import '../services/api_client.dart';
import '../services/assistant_reclamation_service.dart';

class AssistantReclamationProvider extends ChangeNotifier {
  AssistantReclamationProvider({AssistantReclamationService? service})
    : _service = service ?? AssistantReclamationService();

  final AssistantReclamationService _service;

  List<ConversationReclamation> _conversations = const [];
  String _role = 'locataire';
  bool _chargement = false;
  String? _erreur;
  ConversationReclamation? _courante;
  String? _messageEnCours;
  bool _ferme = false;

  List<ConversationReclamation> get conversations => _conversations;
  String get role => _role;
  bool get chargement => _chargement;
  String? get erreur => _erreur;
  ConversationReclamation? get courante => _courante;

  /// Message affiché pendant que l'assistant prépare sa réponse.
  String? get messageEnCours => _messageEnCours;
  bool get envoiEnCours => _messageEnCours != null;
  bool get roleAccepte => _role == 'locataire' || _role == 'proprietaire';

  static String message(Object error) => switch (error) {
    ApiException(horsConnexion: true) =>
      'L’assistant a besoin d’une connexion pour répondre. Votre historique reste consultable.',
    ApiException(:final message) => message,
    _ => 'Une erreur est survenue.',
  };

  Future<void> charger() async {
    _chargement = true;
    _erreur = null;
    notifyListeners();
    try {
      final resultat = await _service.lister();
      _role = resultat.role;
      _conversations = resultat.conversations;
    } catch (error) {
      _erreur = message(error);
    } finally {
      _chargement = false;
      notifyListeners();
    }
  }

  void nouvelle() {
    _courante = null;
    _erreur = null;
    notifyListeners();
  }

  Future<void> ouvrir(ConversationReclamation conversation) async {
    _courante = conversation;
    _erreur = null;
    _chargement = true;
    notifyListeners();
    try {
      _courante = await _service.detail(conversation.id);
    } catch (error) {
      _erreur = message(error);
    } finally {
      _chargement = false;
      notifyListeners();
    }
  }

  /// Retourne false en cas d'échec : le texte reste à renvoyer.
  Future<bool> envoyer(String texte) async {
    if (envoiEnCours) return false;
    _messageEnCours = texte;
    _erreur = null;
    notifyListeners();
    try {
      final actuelle = _courante;
      _courante = actuelle == null
          ? await _service.creer(texte)
          : await _service.envoyer(actuelle.id, texte);
      _majListe();
      return true;
    } catch (error) {
      _erreur = message(error);
      return false;
    } finally {
      _messageEnCours = null;
      notifyListeners();
    }
  }

  Future<void> changerStatut(String statut) async {
    final actuelle = _courante;
    if (actuelle == null) return;
    try {
      _courante = await _service.changerStatut(actuelle.id, statut);
      _majListe();
    } catch (error) {
      _erreur = message(error);
    }
    notifyListeners();
  }

  Future<bool> supprimer(String id) async {
    try {
      await _service.supprimer(id);
      _conversations = _conversations.where((c) => c.id != id).toList();
      if (_courante?.id == id) _courante = null;
      return true;
    } catch (error) {
      _erreur = message(error);
      return false;
    } finally {
      notifyListeners();
    }
  }

  /// Place la conversation à jour en tête de l'historique.
  void _majListe() {
    final courante = _courante;
    if (courante == null) return;
    _conversations = [
      courante,
      ..._conversations.where((c) => c.id != courante.id),
    ];
  }

  @override
  void notifyListeners() {
    if (!_ferme) super.notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    super.dispose();
  }
}
