import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/messagerie.dart';
import '../services/api_client.dart';
import '../services/messagerie_service.dart';
import '../services/traduction_service.dart';
import 'traduction_provider.dart';

/// Liste des conversations et nombre de messages non lus du compte connecté.
class MessagerieProvider extends ChangeNotifier {
  MessagerieProvider({MessagerieService? service}) : _service = service ?? MessagerieService();

  final MessagerieService _service;
  List<ConversationResume> _conversations = const [];
  String? _userId;
  String? _erreur;
  bool _chargement = false;

  List<ConversationResume> get conversations => _conversations;
  String? get erreur => _erreur;
  bool get chargement => _chargement;
  int get nonLus => _conversations.fold(0, (total, c) => total + c.nonLus);

  Future<void> actualiser(String userId) async {
    if (userId != _userId) {
      _userId = userId;
      _conversations = const [];
    }
    _chargement = true;
    notifyListeners();
    try {
      await _service.envoyerFile(userId);
    } on ApiException {
      // Hors connexion : les messages attendent, la liste reste lisible.
    }
    try {
      final liste = await _service.conversations();
      if (userId != _userId) return;
      _conversations = liste;
      _erreur = null;
    } on ApiException catch (erreur) {
      if (userId == _userId) _erreur = erreur.message;
    }
    _chargement = false;
    notifyListeners();
  }
}

/// Une discussion ouverte : messages, suivi régulier, envoi et traduction
/// (une instance par écran).
class DiscussionProvider extends ChangeNotifier {
  DiscussionProvider({
    required this.conversationId,
    required this.userId,
    required this.langueCible,
    required this._service,
    TraductionService? traduction,
    this.periode = const Duration(seconds: 5),
  }) : _traductionService = traduction ?? TraductionService();

  final String conversationId;
  final String userId;

  /// Langue du lecteur (son profil).
  final String langueCible;
  final Duration periode;
  final MessagerieService _service;
  final TraductionService _traductionService;

  List<MessageDiscussion> _serveur = const [];
  List<MessageDiscussion> _attente = const [];
  final Map<String, TraductionMessage> _traductions = {};
  String? _etag;
  String? _erreur;
  bool _chargement = true;
  bool _horsLigne = false;
  bool _enCours = false;
  bool _relancer = false;
  bool _ferme = false;
  Timer? _minuteur;

  bool get chargement => _chargement;
  bool get horsLigne => _horsLigne;
  String? get erreur => _erreur;

  /// Du plus ancien au plus récent ; un message envoyé n'apparaît qu'une fois.
  List<MessageDiscussion> get messages {
    final recus = {for (final m in _serveur) m.clientId};
    return [..._serveur, ..._attente.where((m) => !recus.contains(m.clientId))];
  }

  Future<void> demarrer() async {
    _attente = await _service.enAttente(userId, conversationId);
    try {
      _serveur = (await _service.messages(conversationId)).messages;
    } on ApiException catch (erreur) {
      _erreur = erreur.message;
    }
    if (_ferme) return;
    _chargement = false;
    notifyListeners();
    await actualiser();
    if (_ferme || periode == Duration.zero) return;
    _minuteur = Timer.periodic(periode, (_) => actualiser());
  }

  Future<void> actualiser() async {
    if (_enCours) {
      _relancer = true;
      return;
    }
    _enCours = true;
    try {
      do {
        _relancer = false;
        await _cycle();
      } while (_relancer && !_ferme);
    } finally {
      _enCours = false;
    }
  }

  Future<void> _cycle() async {
    try {
      await _service.envoyerFile(userId, conversationId: conversationId);
      final page = await _service.nouveautes(conversationId, etag: _etag);
      if (page != null) {
        _serveur = page.messages;
        _etag = page.etag;
      }
      _horsLigne = false;
      _erreur = null;
    } on ApiException catch (erreur) {
      if (erreur.horsConnexion) {
        _horsLigne = true;
      } else if (_serveur.isEmpty) {
        _erreur = erreur.message;
      }
    }
    if (_ferme) return;
    _attente = await _service.enAttente(userId, conversationId);
    notifyListeners();
  }

  /// Le message est gardé sur le téléphone puis envoyé dès que possible.
  Future<void> envoyer(String texte, List<String> photos, {required String langueProfil}) async {
    await _service.mettreEnFile(
      userId: userId,
      conversationId: conversationId,
      texte: texte,
      photos: photos,
      langue: langueDuTexte(texte, langueProfil),
    );
    _attente = await _service.enAttente(userId, conversationId);
    notifyListeners();
    await actualiser();
  }

  Future<void> reessayer(String clientId) async {
    await _service.reessayer(clientId);
    await actualiser();
  }

  Future<void> abandonner(String clientId) async {
    await _service.abandonner(clientId);
    _attente = await _service.enAttente(userId, conversationId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Traduction
  // ---------------------------------------------------------------------------

  TraductionMessage traduction(String messageId) => _traductions[messageId] ?? const TraductionMessage();

  /// Un message se traduit s'il vient de l'autre personne et d'une autre langue.
  bool peutTraduire(MessageDiscussion message) =>
      message.auteurId != userId && message.texte.trim().isNotEmpty && message.langue != langueCible;

  /// Le texte ne part vers le service de traduction que sur demande du lecteur.
  Future<void> traduire(MessageDiscussion message) async {
    if (!peutTraduire(message) || traduction(message.id).etat == EtatTraduction.loading) return;
    _traductions[message.id] = TraductionMessage(etat: EtatTraduction.loading, source: message.texte);
    notifyListeners();
    TraductionMessage resultat;
    try {
      final texte = await _traductionService.traduireReponse(
        reponseId: message.id,
        texte: message.texte,
        de: message.langue,
        vers: langueCible,
      );
      resultat = TraductionMessage(etat: EtatTraduction.traduit, texte: texte, afficherTraduction: true, source: message.texte);
    } on TraductionException {
      resultat = TraductionMessage(etat: EtatTraduction.erreur, source: message.texte);
    }
    if (_ferme) return;
    _traductions[message.id] = resultat;
    notifyListeners();
  }

  /// Bascule Original / Traduction.
  void basculerTraduction(String messageId) {
    final actuel = traduction(messageId);
    if (actuel.etat != EtatTraduction.traduit) return;
    _traductions[messageId] = TraductionMessage(
      etat: EtatTraduction.traduit,
      texte: actuel.texte,
      afficherTraduction: !actuel.afficherTraduction,
      source: actuel.source,
    );
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_ferme) super.notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    _minuteur?.cancel();
    super.dispose();
  }
}
