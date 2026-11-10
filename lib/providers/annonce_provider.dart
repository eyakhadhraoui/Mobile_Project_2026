import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/annonce.dart';
import '../services/annonce_cache_service.dart';
import '../services/annonce_file_service.dart';
import '../services/annonce_service.dart';
import '../services/api_client.dart';
import '../services/heure_service.dart';
import '../services/notification_service.dart';
import '../services/photo_storage.dart';
import '../services/planificateur_service.dart';

class AnnonceProvider extends ChangeNotifier {
  AnnonceProvider({
    AnnonceService? service,
    AnnonceCacheService? cache,
    AnnonceFileService? file,
    PhotoStorage? photos,
    PlanificateurService? planificateur,
    HeureService? heure,
    NotificationsPublication? notifications,
    this.intervalle = const Duration(seconds: 20),
    this.intervallePlanificateur = const Duration(seconds: 30),
  }) : _service = service ?? AnnonceService(),
       _cache = cache ?? AnnonceCacheService(),
       _photos = photos ?? PhotoStorage(),
       _notifications = notifications ?? const AucuneNotification() {
    _file = file ?? AnnonceFileService(databaseHelper: _cache.databaseHelper);
    _planificateur = planificateur ?? PlanificateurService(cache: _cache, heure: heure);
  }

  final AnnonceService _service;
  final AnnonceCacheService _cache;
  final PhotoStorage _photos;
  late final AnnonceFileService _file;
  late final PlanificateurService _planificateur;
  final NotificationsPublication _notifications;

  /// Actions faites sans connexion, dans leur ordre d'envoi.
  List<OperationAnnonce> _operations = const [];
  bool _envoiFile = false;
  String? _refusEnvoi;

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

  /// Nombre d'actions qui attendent le retour de la connexion.
  int get actionsEnAttente => _operations.length;

  /// Vrai si l'annonce a été créée, modifiée ou supprimée sans connexion.
  bool estEnAttenteEnvoi(String id) => _operations.any(
    (o) =>
        o.annonceId == id &&
        const [TypeOperationAnnonce.ajouter, TypeOperationAnnonce.modifier].contains(o.type),
  );

  /// Dernière action refusée par le serveur au moment de l'envoi.
  String? get refusEnvoi => _refusEnvoi;

  void oublierRefusEnvoi() {
    _refusEnvoi = null;
    notifyListeners();
  }

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
    _operations = const [];
    _refusEnvoi = null;
    if (ancien != null) {
      // Déconnexion : les notifications appartiennent à l'ancien compte. Le cache
      // reste, lié à ce compte, pour une reconnexion sans réseau.
      _notificationsPlanifiees.clear();
      _sansEchec(_notifications.annulerTout(), 'annulation des notifications');
    }
    // Appelé pendant le build du ProxyProvider : on notifie après le frame.
    scheduleMicrotask(() async {
      if (_dispose || userId != _userId) return;
      if (userId == null) {
        notifyListeners();
        return;
      }
      await _afficherDonneesLocales(userId);
      if (_dispose || userId != _userId) return;
      // Rattrapage au démarrage : publications manquées pendant que le
      // téléphone était éteint ou l'application fermée.
      await rafraichir(recharger: false);
      if (_dispose || userId != _userId) return;
      charger().catchError((_) {});
      _timer = Timer.periodic(intervalle, (_) => charger(silencieux: true).catchError((_) {}));
      _timerPlanificateur = Timer.periodic(intervallePlanificateur, (_) => rafraichir());
    });
  }

  /// Affiche le contenu de l'appareil sans attendre le serveur.
  Future<void> _afficherDonneesLocales(String userId) async {
    try {
      _operations = await _file.lister(userId);
    } on Object catch (error) {
      debugPrint('Lecture de la file d’envoi impossible : $error');
    }
    try {
      final copie = await _cache.lire(userId);
      if (userId != _userId || _annonces.isNotEmpty) return;
      _annonces = _avecFile(copie);
      if (_annonces.isNotEmpty) notifyListeners();
    } on Object catch (error) {
      debugPrint('Lecture du cache impossible : $error');
    }
  }

  List<Annonce> _avecFile(List<Annonce> base) => _operations.fold(base, _appliquer);

  /// Résultat attendu d'une action en file, en attendant la réponse du serveur.
  List<Annonce> _appliquer(List<Annonce> liste, OperationAnnonce op) {
    final copie = [...liste];
    final index = copie.indexWhere((a) => a.id == op.annonceId);
    final actuelle = index < 0 ? null : copie[index];
    switch (op.type) {
      case TypeOperationAnnonce.ajouter:
        final annonce = Annonce.fromJson(op.donnees);
        if (index >= 0) {
          copie[index] = annonce;
        } else {
          copie.insert(0, annonce);
        }
      case TypeOperationAnnonce.modifier:
        if (index >= 0) copie[index] = Annonce.fromJson(op.donnees);
      case TypeOperationAnnonce.supprimer:
        if (index >= 0) copie.removeAt(index);
      case TypeOperationAnnonce.aimer:
        final aime = op.donnees['liked'] == true;
        if (actuelle != null && actuelle.aimeParMoi != aime) {
          copie[index] = actuelle.copyWith(aimeParMoi: aime, likes: actuelle.likes + (aime ? 1 : -1));
        }
      case TypeOperationAnnonce.noter:
        if (actuelle != null) copie[index] = actuelle.copyWith(maNote: op.donnees['note'] as int);
      case TypeOperationAnnonce.commenter:
        if (actuelle != null) copie[index] = actuelle.copyWith(nbCommentaires: actuelle.nbCommentaires + 1);
    }
    return copie;
  }

  /// Vrai si l'annonce n'existe encore que sur cet appareil.
  bool _creeeHorsLigne(String id) =>
      _operations.any((o) => o.annonceId == id && o.type == TypeOperationAnnonce.ajouter);

  /// Enregistre une action. Si [remplace] contient le type d'une action déjà en
  /// file pour cette annonce, celle-ci est mise à jour au lieu d'en ajouter une.
  Future<void> _enFile(
    TypeOperationAnnonce type,
    String annonceId,
    Map<String, dynamic> donnees, {
    Set<TypeOperationAnnonce> remplace = const {},
  }) async {
    final userId = _userId;
    if (userId == null) throw const ApiException('Session expirée : reconnectez-vous.', status: 401);
    final existante = _operations
        .where((o) => o.annonceId == annonceId && remplace.contains(o.type))
        .firstOrNull;
    final OperationAnnonce operation;
    if (existante != null) {
      await _file.remplacerDonnees(existante.id, donnees);
      await _supprimerPhotosLocales(existante);
      operation = existante.avecDonnees(donnees);
      _operations = [for (final o in _operations) o.id == existante.id ? operation : o];
    } else {
      operation = await _file.ajouter(userId, type, annonceId, donnees);
      _operations = [..._operations, operation];
    }
    _annonces = _appliquer(_annonces, operation);
    notifyListeners();
  }

  /// Le sélecteur de photos range ses fichiers dans un dossier temporaire :
  /// ils doivent être copiés pour durer jusqu'à l'envoi.
  Future<List<String>> _photosDurables(List<String> photos) async => [
    for (final photo in photos)
      ApiClient.isRemotePhoto(photo) ? photo : await _photos.copier(photo),
  ];

  Future<void> _supprimerPhotosLocales(OperationAnnonce op) async {
    final photos = op.donnees['photos'];
    if (photos is! List) return;
    for (final photo in photos.whereType<String>()) {
      if (!ApiClient.isRemotePhoto(photo)) await _photos.supprimerSiInterne(photo);
    }
  }

  Future<void> _retirerDeFile(OperationAnnonce op) async {
    await _file.retirer(op.id);
    await _supprimerPhotosLocales(op);
    _operations = _operations.where((o) => o.id != op.id).toList();
  }

  /// Une panne, une session à renouveler ou un compte suspendu peuvent passer :
  /// l'action reste en file. Un refus du serveur (annonce disparue, données
  /// invalides) ne changera pas : l'action est abandonnée et signalée.
  static bool _aRetenter(ApiException error) =>
      error.horsConnexion ||
      error.status == 401 ||
      error.status == 429 ||
      (error.status ?? 0) >= 500 ||
      error.code.startsWith('account_');

  /// Envoie les actions en attente, dans l'ordre. S'arrête à la première panne.
  Future<void> _envoyerFile(String userId) async {
    if (_envoiFile || _operations.isEmpty) return;
    _envoiFile = true;
    try {
      for (final operation in [..._operations]) {
        if (userId != _userId) return;
        try {
          await _executer(operation);
        } on ApiException catch (error) {
          if (_aRetenter(error)) rethrow;
          final dejaSupprimee = operation.type == TypeOperationAnnonce.supprimer && error.status == 404;
          if (!dejaSupprimee) _refusEnvoi = 'Action hors ligne refusée par le serveur : ${error.message}';
        }
        await _retirerDeFile(operation);
        _etag = null;
      }
    } finally {
      _envoiFile = false;
    }
  }

  Future<void> _executer(OperationAnnonce op) async {
    Annonce annonce() {
      final lue = Annonce.fromJson(op.donnees);
      final date = lue.datePublication;
      // La date prévue est passée pendant l'absence de réseau : publication immédiate.
      return date != null && !date.isAfter(DateTime.now()) ? lue.copyWith(datePublication: null) : lue;
    }

    switch (op.type) {
      case TypeOperationAnnonce.ajouter:
        await _service.ajouterDepuisFile(annonce());
      case TypeOperationAnnonce.modifier:
        await _service.modifier(annonce());
      case TypeOperationAnnonce.supprimer:
        await _service.supprimer(op.annonceId);
      case TypeOperationAnnonce.aimer:
        await _service.aimer(op.annonceId, op.donnees['liked'] == true);
      case TypeOperationAnnonce.noter:
        await _service.noter(op.annonceId, op.donnees['note'] as int);
      case TypeOperationAnnonce.commenter:
        await _service.commenter(op.annonceId, op.donnees['text'] as String);
    }
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
      await _envoyerFile(userId);
      final page = await _service.lister(etag: silencieux ? _etag : null);
      if (userId != _userId) return;
      _erreur = null;
      _horsLigne = false;
      if (page != null) {
        _annonces = _avecFile(page.annonces);
        _role = page.meRole;
        _moderation = page.moderation;
        _etag = page.etag;
        await _sansEchec(_cache.remplacer(userId, page.annonces), 'mise à jour du cache');
        await _synchroniserNotifications(page.annonces);
      }
    } catch (error) {
      if (userId != _userId) return;
      _erreur = error;
      if (error is ApiException && (error.isNetwork || error.horsConnexion)) {
        _horsLigne = true;
        if (_annonces.isEmpty) {
          try {
            _annonces = _avecFile(await _cache.lire(userId));
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

  Future<CorrespondancePhoto?> verifierPhoto(String chemin) => _service.verifierPhoto(chemin);

  Future<Annonce> ajouter(Annonce annonce) async {
    try {
      final cree = await _service.ajouter(annonce);
      _remplacer(cree, ajouterEnTete: true);
      return cree;
    } on ApiException catch (error) {
      if (!error.horsConnexion) rethrow;
      return _ajouterHorsLigne(annonce);
    }
  }

  Future<Annonce> _ajouterHorsLigne(Annonce annonce) async {
    final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final photos = await _photosDurables(annonce.photos);
    final locale = Annonce.fromJson({
      ...annonce.copyWith(photos: photos).toJson(),
      'id': id,
      'statut': annonce.datePublication != null
          ? StatutAnnonce.programmee.name
          : _moderation
          ? StatutAnnonce.enAttente.name
          : StatutAnnonce.publiee.name,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _enFile(TypeOperationAnnonce.ajouter, id, locale.toJson());
    return locale;
  }

  Future<Annonce> modifier(Annonce annonce) async {
    if (_creeeHorsLigne(annonce.id)) return _modifierHorsLigne(annonce);
    try {
      final modifiee = await _service.modifier(annonce);
      _remplacer(modifiee);
      return modifiee;
    } on ApiException catch (error) {
      if (!error.horsConnexion) rethrow;
      return _modifierHorsLigne(annonce);
    }
  }

  Future<Annonce> _modifierHorsLigne(Annonce annonce) async {
    final actuelle = parId(annonce.id);
    if (actuelle == null) throw const ApiException('Annonce introuvable sur cet appareil.', status: 404);
    final photos = await _photosDurables(annonce.photos);
    final champs = annonce.copyWith(photos: photos).toPayload();
    final programmee = annonce.datePublication != null;
    final locale = Annonce.fromJson({
      ...actuelle.toJson(),
      ...champs,
      'statut': programmee
          ? StatutAnnonce.programmee.name
          : actuelle.estProgrammee
          ? _statutCible(actuelle).name
          : actuelle.statut.name,
    });
    await _enFile(
      TypeOperationAnnonce.modifier,
      annonce.id,
      locale.toJson(),
      remplace: const {TypeOperationAnnonce.ajouter, TypeOperationAnnonce.modifier},
    );
    return locale;
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

  Future<void> _supprimerHorsLigne(String id) async {
    final jamaisEnvoyee = _creeeHorsLigne(id);
    for (final operation in _operations.where((o) => o.annonceId == id).toList()) {
      await _retirerDeFile(operation);
    }
    if (!jamaisEnvoyee) await _enFile(TypeOperationAnnonce.supprimer, id, const {});
  }

  Future<void> supprimer(String id) async {
    if (_creeeHorsLigne(id)) {
      await _supprimerHorsLigne(id);
    } else {
      try {
        await _service.supprimer(id);
      } on ApiException catch (error) {
        if (!error.horsConnexion) rethrow;
        await _supprimerHorsLigne(id);
      }
    }
    _annonces = _annonces.where((a) => a.id != id).toList();
    _etag = null;
    await _oublierNotification(id);
    if (!_operations.any((o) => o.annonceId == id)) {
      _sansEchec(_cache.supprimer(id), 'suppression du cache');
    }
    notifyListeners();
  }

  Future<void> changerStatut(String id, StatutAnnonce statut, {String motif = ''}) async =>
      _remplacer(await _service.changerStatut(id, statut, motif: motif));

  Future<void> noter(String id, int note) async {
    Future<void> enFile() => _enFile(
      TypeOperationAnnonce.noter,
      id,
      {'note': note},
      remplace: const {TypeOperationAnnonce.noter},
    );
    if (_creeeHorsLigne(id)) return enFile();
    try {
      _remplacer(await _service.noter(id, note));
    } on ApiException catch (error) {
      if (!error.horsConnexion) rethrow;
      await enFile();
    }
  }

  /// Like optimiste : l'interface change tout de suite. Sans connexion il attend
  /// en file ; si le serveur le refuse, il revient en arrière.
  Future<void> basculerLike(Annonce annonce) async {
    final aime = !annonce.aimeParMoi;
    Future<void> enFile() => _enFile(
      TypeOperationAnnonce.aimer,
      annonce.id,
      {'liked': aime},
      remplace: const {TypeOperationAnnonce.aimer},
    );
    _remplacer(annonce.copyWith(aimeParMoi: aime, likes: annonce.likes + (aime ? 1 : -1)));
    if (_creeeHorsLigne(annonce.id)) return enFile();
    try {
      await _service.aimer(annonce.id, aime);
    } on ApiException catch (error) {
      if (error.horsConnexion) return enFile();
      _remplacer(annonce);
      rethrow;
    } catch (_) {
      _remplacer(annonce);
      rethrow;
    }
  }

  /// Commentaires connus (copie locale sans connexion), plus ceux en attente d'envoi.
  Future<List<CommentaireAnnonce>> commentaires(String id) async {
    List<CommentaireAnnonce> connus = const [];
    if (!_creeeHorsLigne(id)) {
      try {
        connus = await _service.commentaires(id);
      } on ApiException catch (error) {
        if (!error.horsConnexion) rethrow;
      }
    }
    return [
      ...connus,
      for (final o in _operations)
        if (o.annonceId == id && o.type == TypeOperationAnnonce.commenter)
          CommentaireAnnonce(userId: _userId ?? '', auteur: 'Vous (en attente d’envoi)', texte: o.donnees['text'] as String),
    ];
  }

  Future<List<CommentaireAnnonce>> commenter(String id, String texte) async {
    Future<List<CommentaireAnnonce>> enFile() async {
      await _enFile(TypeOperationAnnonce.commenter, id, {'text': texte});
      return commentaires(id);
    }

    if (_creeeHorsLigne(id)) return enFile();
    try {
      final result = await _service.commenter(id, texte);
      charger(silencieux: true).catchError((_) {});
      return result;
    } on ApiException catch (error) {
      if (!error.horsConnexion) rethrow;
      return enFile();
    }
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
