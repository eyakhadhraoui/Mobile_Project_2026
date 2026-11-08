import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/annonce.dart';
import '../services/annonce_cache_service.dart';
import '../services/annonce_service.dart';
import '../services/api_client.dart';
import '../services/heure_service.dart';
import '../services/notification_service.dart';
import '../services/planificateur_service.dart';

class AnnonceProvider extends ChangeNotifier {
  AnnonceProvider({
    AnnonceService? service,
    AnnonceCacheService? cache,
    PlanificateurService? planificateur,
    HeureService? heure,
    NotificationsPublication? notifications,
    this.intervalle = const Duration(seconds: 20),
    this.intervallePlanificateur = const Duration(seconds: 30),
  }) : _service = service ?? AnnonceService(),
       _cache = cache ?? AnnonceCacheService(),
       _notifications = notifications ?? const AucuneNotification() {
    _planificateur = planificateur ?? PlanificateurService(cache: _cache, heure: heure);
  }

  final AnnonceService _service;
  final AnnonceCacheService _cache;
  late final PlanificateurService _planificateur;
  final NotificationsPublication _notifications;

  /// Rechargement silencieux depuis le serveur (ETag).
  final Duration intervalle;

  /// Passage du planificateur local tant que l'application est ouverte.
  final Duration intervallePlanificateur;

  List<Annonce> _annonces = const [];
  bool _chargement = false;
  Object? _erreur;
  bool _horsLigne = false;
  bool _operationEnCours = false;
  Object? _erreurOperation;
  String? _etag;
  String? _userId;
  String _role = '';
  bool _moderation = false;
  Timer? _timer;
  Timer? _timerPlanificateur;
  bool _migrationFaite = false;
  bool _dispose = false;

  /// Notifications planifiées sur cet appareil : identifiant → date prévue.
  final Map<String, DateTime> _notificationsPlanifiees = {};

  List<Annonce> get annonces => List.unmodifiable(_annonces);
  bool get chargement => _chargement;
  bool get isLoading => _chargement;
  Object? get erreur => _erreur;

  /// Vrai quand la liste affichée vient du cache SQLite (serveur injoignable).
  bool get horsLigne => _horsLigne;

  /// Programmation ou annulation en cours, et sa dernière erreur.
  bool get operationEnCours => _operationEnCours;
  Object? get erreurOperation => _erreurOperation;

  bool get estAdmin => _role == 'administrateur';
  bool get moderation => _moderation;
  int get aModerer => _annonces.where((a) => a.statut == StatutAnnonce.enAttente).length;

  Annonce? parId(String id) {
    for (final annonce in _annonces) {
      if (annonce.id == id) return annonce;
    }
    return null;
  }

  /// Appelé par le ProxyProvider à chaque changement de session.
  void utilisateur(String? userId) {
    if (userId == _userId) return;
    final ancien = _userId;
    _timer?.cancel();
    _timerPlanificateur?.cancel();
    _userId = userId;
    _annonces = const [];
    _etag = null;
    _role = '';
    _moderation = false;
    _erreur = null;
    _horsLigne = false;
    _migrationFaite = false;
    if (ancien != null) {
      // Déconnexion : les notifications et le cache appartiennent à l'ancien compte.
      _notificationsPlanifiees.clear();
      _sansEchec(_notifications.annulerTout(), 'annulation des notifications');
      _sansEchec(_cache.vider(), 'vidage du cache');
    }
    // Appelé pendant le build du ProxyProvider : on notifie après le frame.
    scheduleMicrotask(() async {
      if (_dispose || userId != _userId) return;
      if (userId == null) {
        notifyListeners();
        return;
      }
      // Rattrapage au démarrage : publications manquées pendant que le
      // téléphone était éteint ou l'application fermée.
      await rafraichir(recharger: false);
      if (_dispose || userId != _userId) return;
      charger().catchError((_) {});
      _timer = Timer.periodic(intervalle, (_) => charger(silencieux: true).catchError((_) {}));
      _timerPlanificateur = Timer.periodic(intervallePlanificateur, (_) => rafraichir());
    });
  }

  /// Recharge la liste. En mode silencieux, l'ETag évite de retélécharger une
  /// liste inchangée et aucun indicateur de chargement n'est affiché.
  /// Serveur injoignable : on affiche la copie SQLite (mode hors ligne).
  Future<void> charger({bool silencieux = false}) async {
    final userId = _userId;
    if (userId == null) return;
    if (!silencieux) {
      _chargement = true;
      notifyListeners();
    }
    try {
      if (!_migrationFaite && !silencieux) {
        try {
          await _service.migrerAnnoncesLocales(userId);
          _migrationFaite = true;
        } catch (error) {
          // Ne bloque pas l'affichage : nouvel essai au prochain chargement manuel.
          debugPrint('Migration des annonces locales impossible : $error');
        }
      }
      final page = await _service.lister(etag: silencieux ? _etag : null);
      if (userId != _userId) return;
      _erreur = null;
      _horsLigne = false;
      if (page != null) {
        _annonces = page.annonces;
        _role = page.meRole;
        _moderation = page.moderation;
        _etag = page.etag;
        await _sansEchec(_cache.remplacer(userId, page.annonces), 'mise à jour du cache');
        await _synchroniserNotifications(page.annonces);
      }
    } catch (error) {
      if (userId != _userId) return;
      _erreur = error;
      if (error is ApiException && error.isNetwork) {
        _horsLigne = true;
        if (_annonces.isEmpty) {
          try {
            _annonces = await _cache.lire(userId);
          } catch (cacheError) {
            debugPrint('Lecture du cache impossible : $cacheError');
          }
        }
      }
      if (!silencieux) rethrow;
    } finally {
      if (userId == _userId) {
        _chargement = false;
        notifyListeners();
      }
    }
  }

  /// Lance le planificateur local puis, si des annonces ont été publiées,
  /// met à jour la liste et resynchronise avec le serveur.
  /// Appelé au démarrage, à la reprise de l'application et toutes les 30 s.
  /// Retourne le nombre d'annonces publiées.
  Future<int> rafraichir({bool recharger = true}) async {
    final userId = _userId;
    if (userId == null) return 0;
    final List<Annonce> publiees;
    try {
      publiees = await _planificateur.publierAnnoncesEchues(userId: userId, statutCible: _statutCible);
    } catch (error) {
      debugPrint('Planificateur des annonces : $error');
      return 0;
    }
    if (_dispose || userId != _userId || publiees.isEmpty) return 0;
    final parIdentifiant = {for (final a in publiees) a.id: a};
    _annonces = [
      for (final a in _annonces)
        parIdentifiant.containsKey(a.id) ? a.copyWith(statut: parIdentifiant[a.id]!.statut) : a,
    ];
    // La notification a déjà été affichée à l'heure prévue : on l'oublie sans l'annuler.
    for (final a in publiees) {
      _notificationsPlanifiees.remove(a.id);
    }
    _etag = null;
    notifyListeners();
    if (recharger) unawaited(charger(silencieux: true).catchError((_) {}));
    return publiees.length;
  }

  /// Statut d'une annonce programmée à son échéance (règle identique au serveur).
  StatutAnnonce _statutCible(Annonce annonce) {
    final auteurAdmin = estAdmin && annonce.proprietaireId == _userId;
    return _moderation && !auteurAdmin ? StatutAnnonce.enAttente : StatutAnnonce.publiee;
  }

  Future<Annonce> ajouter(Annonce annonce) async {
    final cree = await _service.ajouter(annonce);
    _remplacer(cree, ajouterEnTete: true);
    return cree;
  }

  Future<Annonce> modifier(Annonce annonce) async {
    final modifiee = await _service.modifier(annonce);
    _remplacer(modifiee);
    return modifiee;
  }

  /// Programme la publication de [annonce] à [date] (UTC ou locale).
  Future<Annonce> programmer(Annonce annonce, DateTime date) =>
      _operation(() => _service.programmer(annonce.id, date));

  /// Annule la programmation de l'annonce [id] : publication immédiate
  /// (ou validation) si [publierMaintenant], sinon retour « en attente ».
  Future<Annonce> annulerProgrammation(String id, {bool publierMaintenant = true}) =>
      _operation(() => _service.annulerProgrammation(id, publierMaintenant: publierMaintenant));

  /// Demande les permissions de notification (et d'alarmes exactes sur Android 12+).
  Future<bool> demanderPermissionsNotifications() async {
    try {
      return await _notifications.demanderPermissions();
    } catch (error) {
      debugPrint('Permissions de notification : $error');
      return false;
    }
  }

  Future<Annonce> _operation(Future<Annonce> Function() action) async {
    _operationEnCours = true;
    _erreurOperation = null;
    notifyListeners();
    try {
      final annonce = await action();
      _remplacer(annonce);
      return annonce;
    } catch (error) {
      _erreurOperation = error;
      rethrow;
    } finally {
      _operationEnCours = false;
      notifyListeners();
    }
  }

  Future<void> supprimer(String id) async {
    await _service.supprimer(id);
    _annonces = _annonces.where((a) => a.id != id).toList();
    _etag = null;
    await _oublierNotification(id);
    _sansEchec(_cache.supprimer(id), 'suppression du cache');
    notifyListeners();
  }

  Future<void> changerStatut(String id, StatutAnnonce statut, {String motif = ''}) async =>
      _remplacer(await _service.changerStatut(id, statut, motif: motif));

  Future<void> noter(String id, int note) async => _remplacer(await _service.noter(id, note));

  /// Like optimiste : l'interface change tout de suite, puis revient en arrière en cas d'échec.
  Future<void> basculerLike(Annonce annonce) async {
    final aime = !annonce.aimeParMoi;
    _remplacer(annonce.copyWith(aimeParMoi: aime, likes: annonce.likes + (aime ? 1 : -1)));
    try {
      await _service.aimer(annonce.id, aime);
    } catch (_) {
      _remplacer(annonce);
      rethrow;
    }
  }

  Future<List<CommentaireAnnonce>> commentaires(String id) => _service.commentaires(id);

  Future<List<CommentaireAnnonce>> commenter(String id, String texte) async {
    final result = await _service.commenter(id, texte);
    charger(silencieux: true).catchError((_) {});
    return result;
  }

  void _remplacer(Annonce annonce, {bool ajouterEnTete = false}) {
    final index = _annonces.indexWhere((a) => a.id == annonce.id);
    final copie = [..._annonces];
    if (index >= 0) {
      copie[index] = annonce;
    } else if (ajouterEnTete) {
      copie.insert(0, annonce);
    }
    _annonces = copie;
    _etag = null;
    final userId = _userId;
    if (userId != null) _sansEchec(_cache.enregistrer(userId, annonce), 'mise à jour du cache');
    _sansEchec(_synchroniserNotification(annonce), 'notification');
    notifyListeners();
  }

  /// Planifie les notifications des annonces programmées de l'utilisateur et
  /// annule celles qui ne sont plus programmées (annulation, suppression).
  Future<void> _synchroniserNotifications(List<Annonce> annonces) async {
    final vues = <String>{};
    for (final annonce in annonces.where((a) => a.proprietaireId == _userId)) {
      vues.add(annonce.id);
      await _sansEchec(_synchroniserNotification(annonce), 'notification');
    }
    for (final id in _notificationsPlanifiees.keys.where((id) => !vues.contains(id)).toList()) {
      await _sansEchec(_oublierNotification(id), 'notification');
    }
  }

  Future<void> _synchroniserNotification(Annonce annonce) async {
    if (annonce.proprietaireId != _userId) return;
    final date = annonce.datePublication;
    if (annonce.estProgrammee && date != null) {
      if (_notificationsPlanifiees[annonce.id] == date) return;
      _notificationsPlanifiees[annonce.id] = date;
      await _notifications.programmer(
        annonceId: annonce.id,
        titre: annonce.titre,
        date: date,
        enValidation: _statutCible(annonce) == StatutAnnonce.enAttente,
      );
    } else {
      await _oublierNotification(annonce.id);
    }
  }

  /// Annule la notification si elle n'a pas encore été affichée
  /// (une notification déjà affichée reste dans la barre de notifications).
  Future<void> _oublierNotification(String id) async {
    final date = _notificationsPlanifiees.remove(id);
    if (date != null && date.isAfter(DateTime.now())) await _notifications.annuler(id);
  }

  /// Le cache et les notifications ne doivent jamais bloquer l'affichage.
  Future<void> _sansEchec(Future<void> action, String quoi) =>
      action.catchError((Object error) => debugPrint('Annonces ($quoi) : $error'));

  @override
  void notifyListeners() {
    // Une requête peut se terminer après la fermeture du provider.
    if (!_dispose) super.notifyListeners();
  }

  @override
  void dispose() {
    _dispose = true;
    _timer?.cancel();
    _timerPlanificateur?.cancel();
    super.dispose();
  }
}
