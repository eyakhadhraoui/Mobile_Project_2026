import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  /// Version du schéma. 10 : publication programmée des annonces
  /// (colonne `date_publication`) et cache hors ligne des annonces du serveur.
  /// 11 : langue des utilisateurs, échanges des réclamations et cache des traductions.
  /// 12 : cache du géocodage des adresses de logement (carte des réclamations).
  /// 13 : cache des temps de trajet logement → université (OSRM).
  /// 14 : module Covoiturage (préfixe `covoiturage_` pour ne pas entrer en
  /// collision avec la table `trajets` déjà utilisée par le cache OSRM).
  /// 15 : coordonnées facultatives des publications de covoiturage pour la carte.
  /// 16 : alertes sauvegardées de covoiturage.
  /// 17 : demandes de maintenance liées aux comptes et historique des statuts.
  /// 18 : logements loués et rattachement des demandes de maintenance.
  /// 19 : nom du propriétaire conservé dans la demande de maintenance.
  /// 21 : messages de la messagerie en attente d'envoi.
  /// 22 : copie locale des données du serveur et suivi de la synchronisation.
  static const versionSchema = 22;

  DatabaseHelper._({this._path});

  static final DatabaseHelper instance = DatabaseHelper._();

  /// A separate helper for tests, typically with [path] set to ':memory:'.
  factory DatabaseHelper.forTests({String path = ':memory:'}) =>
      DatabaseHelper._(path: path);

  final String? _path;
  Future<Database>? _opening;

  Future<Database> get database {
    final opened = _opening;
    if (opened != null) return opened;
    final future = _open().catchError((Object error, StackTrace stackTrace) {
      _opening = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    _opening = future;
    return future;
  }

  Future<Database> _open() async {
    final path = _path ?? p.join(await getDatabasesPath(), 'studenthub.db');
    return openDatabase(
      path,
      version: versionSchema,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY, nom TEXT NOT NULL, prenom TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE COLLATE NOCASE, telephone TEXT NOT NULL UNIQUE,
        rolePrincipal TEXT NOT NULL, roleSecondaire TEXT, photo TEXT,
        preferences TEXT NOT NULL DEFAULT '{}', passwordHash TEXT NOT NULL,
        passwordSalt TEXT NOT NULL, createdAt TEXT NOT NULL,
        emailVerified INTEGER NOT NULL DEFAULT 0,
        accountStatus TEXT NOT NULL DEFAULT 'pending', isRemote INTEGER NOT NULL DEFAULT 0,
        langue TEXT NOT NULL DEFAULT 'fr'
      )
    ''');
    await db.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute('''
      CREATE TABLE complaints (
        id TEXT PRIMARY KEY, userId TEXT NOT NULL, locationId TEXT NOT NULL,
        subject TEXT NOT NULL, category TEXT NOT NULL, description TEXT NOT NULL,
        photos TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL,
        priority TEXT NOT NULL DEFAULT 'moyenne', isDraft INTEGER NOT NULL DEFAULT 0,
        syncStatus TEXT NOT NULL DEFAULT 'pending', isDeleted INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE complaint_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT, complaintId TEXT NOT NULL,
        status TEXT NOT NULL, date TEXT NOT NULL,
        FOREIGN KEY (complaintId) REFERENCES complaints(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX complaints_user_date ON complaints(userId, createdAt DESC)',
    );
    await _createAnnonces(db);
    await _createHousingTables(db);
    await _creerTablesEchanges(db);
    await _creerTableGeocodage(db);
    await _creerTableTrajets(db);
    await _creerTablesCovoiturage(db);
    await _creerTableAlertesTrajet(db);
    await _createDemandes(db);
    await _createLogementsLoues(db);
    await _createAnnoncesFile(db);
    await _createMessagesFile(db);
    await _createMiroir(db);
  }

  /// Double stockage : suivi des lignes synchronisées, et tables qui recopient
  /// des données tenues par le serveur.
  Future<void> _createMiroir(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS miroir_etat (
      source TEXT NOT NULL, cle TEXT NOT NULL, valeur TEXT NOT NULL,
      PRIMARY KEY (source, cle))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS annonce_likes (
      annonceId TEXT NOT NULL, userId TEXT NOT NULL, author TEXT, createdAt TEXT,
      PRIMARY KEY (annonceId, userId))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS annonce_commentaires (
      annonceId TEXT NOT NULL, userId TEXT NOT NULL, author TEXT, text TEXT NOT NULL, createdAt TEXT NOT NULL,
      PRIMARY KEY (annonceId, userId, createdAt))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS annonce_avis (
      annonceId TEXT NOT NULL, userId TEXT NOT NULL, note INTEGER NOT NULL, author TEXT, createdAt TEXT,
      PRIMARY KEY (annonceId, userId))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS messagerie_conversations (
      id TEXT PRIMARY KEY, annonceId TEXT NOT NULL, annonceTitre TEXT, locataireId TEXT NOT NULL,
      proprietaireId TEXT NOT NULL, createdAt TEXT, updatedAt TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS messagerie_messages (
      id TEXT PRIMARY KEY, conversationId TEXT NOT NULL, auteurId TEXT NOT NULL, texte TEXT NOT NULL,
      photos TEXT NOT NULL DEFAULT '[]', langue TEXT, clientId TEXT, createdAt TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS assistant_conversations (
      id TEXT PRIMARY KEY, userId TEXT NOT NULL, updatedAt TEXT, donnees TEXT NOT NULL)''');
  }

  /// Messages écrits sans connexion, envoyés dans l'ordre au retour du réseau.
  Future<void> _createMessagesFile(DatabaseExecutor db) => db.execute(
    '''CREATE TABLE IF NOT EXISTS messages_file (
      clientId TEXT PRIMARY KEY,
      userId TEXT NOT NULL,
      conversationId TEXT NOT NULL,
      texte TEXT NOT NULL,
      photos TEXT NOT NULL,
      langue TEXT NOT NULL,
      etat TEXT NOT NULL,
      erreur TEXT,
      createdAt TEXT NOT NULL
    )''',
  );

  /// Actions sur les annonces faites sans connexion, envoyées dans l'ordre.
  Future<void> _createAnnoncesFile(DatabaseExecutor db) => db.execute(
    '''CREATE TABLE IF NOT EXISTS annonces_file (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId TEXT NOT NULL,
      type TEXT NOT NULL,
      annonceId TEXT NOT NULL,
      donnees TEXT NOT NULL,
      createdAt TEXT NOT NULL
    )''',
  );

  /// Demandes de maintenance et historique de leurs statuts.
  Future<void> _createDemandes(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS demandes (
      id TEXT PRIMARY KEY, userId TEXT NOT NULL, assigneeId TEXT,
      category TEXT NOT NULL, room TEXT NOT NULL, urgency TEXT NOT NULL,
      title TEXT NOT NULL, description TEXT NOT NULL,
      residentName TEXT NOT NULL, residentPhone TEXT NOT NULL, photoPath TEXT,
      statut TEXT NOT NULL, createdAt TEXT NOT NULL,
      logementId TEXT, logementTitre TEXT, proprietaireId TEXT, proprietaireNom TEXT,
      FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (assigneeId) REFERENCES users(id) ON DELETE SET NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS demande_historique (
      id INTEGER PRIMARY KEY AUTOINCREMENT, demandeId TEXT NOT NULL,
      statut TEXT NOT NULL, date TEXT NOT NULL, auteurId TEXT,
      FOREIGN KEY (demandeId) REFERENCES demandes(id) ON DELETE CASCADE,
      FOREIGN KEY (auteurId) REFERENCES users(id) ON DELETE SET NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS demandes_user ON demandes(userId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS demandes_assignee ON demandes(assigneeId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS demande_historique_demande ON demande_historique(demandeId)',
    );
  }

  /// Copie locale des logements loués (les locations vivent sur le serveur).
  Future<void> _createLogementsLoues(DatabaseExecutor db) => db.execute(
    '''CREATE TABLE IF NOT EXISTS logements_loues (
      userId TEXT NOT NULL, annonceId TEXT NOT NULL, titre TEXT NOT NULL,
      adresse TEXT NOT NULL, proprietaireId TEXT NOT NULL,
      proprietaireNom TEXT NOT NULL, debut TEXT NOT NULL, fin TEXT NOT NULL,
      PRIMARY KEY (userId, annonceId),
      FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE)''',
  );

  /// Temps de trajet déjà calculés. depart / arrivee : « lat,lon » arrondis à
  /// 5 décimales (~1 m). duree NULL : aucun itinéraire trouvé.
  Future<void> _creerTableTrajets(DatabaseExecutor db) =>
      db.execute('''CREATE TABLE IF NOT EXISTS trajets (
      depart TEXT NOT NULL, arrivee TEXT NOT NULL, mode TEXT NOT NULL,
      duree REAL, distance REAL, date TEXT NOT NULL,
      PRIMARY KEY (depart, arrivee, mode))''');

  /// Coordonnées des adresses déjà géocodées (clé : adresse normalisée).
  /// introuvable = 1 : Nominatim n'a rien trouvé (on ne redemande pas tout de suite).
  Future<void> _creerTableGeocodage(DatabaseExecutor db) =>
      db.execute('''CREATE TABLE IF NOT EXISTS geocodage (
      adresse TEXT PRIMARY KEY, lat REAL, lon REAL, libelle TEXT,
      introuvable INTEGER NOT NULL DEFAULT 0, date TEXT NOT NULL)''');

  /// Échanges d'une réclamation (réponses du propriétaire, messages de
  /// l'étudiant) et cache des traductions automatiques de ces messages.
  Future<void> _creerTablesEchanges(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS complaint_responses (
      id TEXT PRIMARY KEY, complaintId TEXT NOT NULL, authorId TEXT NOT NULL,
      authorRole TEXT NOT NULL, text TEXT NOT NULL, langue TEXT NOT NULL DEFAULT 'fr',
      createdAt TEXT NOT NULL, updatedAt TEXT,
      syncStatus TEXT NOT NULL DEFAULT 'pending', isDeleted INTEGER NOT NULL DEFAULT 0)''',
    );
    // Pas de clé étrangère en cascade : la synchronisation réécrit les réclamations
    // avec INSERT OR REPLACE, ce qui effacerait les messages non encore envoyés.
    // ComplaintService supprime les messages lui-même quand la réclamation disparaît.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS complaint_responses_complaint ON complaint_responses(complaintId, createdAt)',
    );
    // Une seule traduction par message et par langue (clé unique reponse_id + langue).
    await db.execute('''CREATE TABLE IF NOT EXISTS traductions (
      id INTEGER PRIMARY KEY AUTOINCREMENT, reponse_id TEXT NOT NULL,
      langue TEXT NOT NULL, texte_traduit TEXT NOT NULL, date TEXT NOT NULL,
      UNIQUE (reponse_id, langue))''');
  }

  Future<void> _createAnnonces(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE annonces (
        id TEXT PRIMARY KEY,
        titre TEXT NOT NULL,
        description TEXT NOT NULL,
        typeLocation TEXT NOT NULL,
        loyer REAL NOT NULL,
        surface REAL NOT NULL,
        chambres INTEGER NOT NULL,
        etage INTEGER,
        ville TEXT NOT NULL,
        quartier TEXT NOT NULL,
        adresse TEXT NOT NULL,
        photos TEXT NOT NULL DEFAULT '[]',
        statut TEXT NOT NULL DEFAULT 'enAttente',
        proprietaireId TEXT NOT NULL,
        commentaires TEXT NOT NULL DEFAULT '[]',
        autoriserCommentaires INTEGER NOT NULL DEFAULT 1,
        categorie TEXT NOT NULL DEFAULT '',
        date_publication TEXT,
        cache_utilisateur TEXT,
        donnees TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX annonces_proprietaire ON annonces(proprietaireId)',
    );
    await _creerIndexProgrammation(db);
  }

  /// Index utilisé par le planificateur (annonces programmées échues).
  Future<void> _creerIndexProgrammation(DatabaseExecutor db) => db.execute(
    'CREATE INDEX IF NOT EXISTS annonces_programmation '
    'ON annonces(cache_utilisateur, statut, date_publication)',
  );

  /// Ajoute une colonne seulement si elle n'existe pas encore : une base
  /// créée directement dans une version récente l'a déjà.
  Future<void> _ajouterColonne(
    DatabaseExecutor db,
    String table,
    String colonne,
    String definition,
  ) async {
    final colonnes = await db.rawQuery('PRAGMA table_info($table)');
    if (colonnes.any((c) => c['name'] == colonne)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $colonne $definition');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE complaints ADD COLUMN priority TEXT NOT NULL DEFAULT 'moyenne'",
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE users ADD COLUMN emailVerified INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute(
        "ALTER TABLE users ADD COLUMN accountStatus TEXT NOT NULL DEFAULT 'approved'",
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE complaints ADD COLUMN isDraft INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        "ALTER TABLE complaints ADD COLUMN syncStatus TEXT NOT NULL DEFAULT 'pending'",
      );
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE complaints ADD COLUMN isDeleted INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE users ADD COLUMN isRemote INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 7) await _createAnnonces(db);
    if (oldVersion < 8) {
      await _ajouterColonne(
        db,
        'annonces',
        'commentaires',
        "TEXT NOT NULL DEFAULT '[]'",
      );
      await _ajouterColonne(
        db,
        'annonces',
        'autoriserCommentaires',
        'INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 9) await _createHousingTables(db);
    if (oldVersion < 10) {
      // Migration sans perte : les lignes existantes gardent leurs valeurs ;
      // les nouvelles colonnes sont vides (NULL) pour elles.
      // date_publication : ISO 8601 UTC (ex. 2026-11-05T13:00:00.000Z).
      await _ajouterColonne(db, 'annonces', 'date_publication', 'TEXT');
      await _ajouterColonne(
        db,
        'annonces',
        'categorie',
        "TEXT NOT NULL DEFAULT ''",
      );
      // NULL : ancienne annonce locale à envoyer au serveur ;
      // sinon : copie hors ligne d'une annonce serveur vue par cet utilisateur.
      await _ajouterColonne(db, 'annonces', 'cache_utilisateur', 'TEXT');
      await _ajouterColonne(db, 'annonces', 'donnees', 'TEXT');
      await _creerIndexProgrammation(db);
    }
    if (oldVersion < 11) {
      // Les comptes existants gardent leurs données et lisent en français.
      await _ajouterColonne(
        db,
        'users',
        'langue',
        "TEXT NOT NULL DEFAULT 'fr'",
      );
      await _creerTablesEchanges(db);
    }
    if (oldVersion < 12) await _creerTableGeocodage(db);
    if (oldVersion < 13) await _creerTableTrajets(db);
    if (oldVersion < 14) await _creerTablesCovoiturage(db);
    if (oldVersion < 15) {
      await _ajouterColonne(db, 'covoiturage_trajets', 'departLat', 'REAL');
      await _ajouterColonne(db, 'covoiturage_trajets', 'departLng', 'REAL');
      await _ajouterColonne(db, 'covoiturage_trajets', 'arriveeLat', 'REAL');
      await _ajouterColonne(db, 'covoiturage_trajets', 'arriveeLng', 'REAL');
    }
    if (oldVersion < 16) await _creerTableAlertesTrajet(db);
    if (oldVersion < 17) await _createDemandes(db);
    if (oldVersion < 18) {
      await _ajouterColonne(db, 'demandes', 'logementId', 'TEXT');
      await _ajouterColonne(db, 'demandes', 'logementTitre', 'TEXT');
      await _ajouterColonne(db, 'demandes', 'proprietaireId', 'TEXT');
      await _createLogementsLoues(db);
    }
    if (oldVersion < 19) {
      await _ajouterColonne(db, 'demandes', 'proprietaireNom', 'TEXT');
    }
    if (oldVersion < 20) await _createAnnoncesFile(db);
    if (oldVersion < 21) await _createMessagesFile(db);
    if (oldVersion < 22) await _createMiroir(db);
  }

  Future<void> _creerTablesCovoiturage(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS covoiturage_trajets (
      id TEXT PRIMARY KEY, auteurId TEXT NOT NULL, auteurNom TEXT NOT NULL,
      type TEXT NOT NULL, depart TEXT NOT NULL, arrivee TEXT NOT NULL,
      zone TEXT NOT NULL, date TEXT NOT NULL, heure TEXT NOT NULL,
      places INTEGER NOT NULL, prix REAL, commentaire TEXT NOT NULL DEFAULT '',
      statut TEXT NOT NULL DEFAULT 'ouvert',
      departLat REAL, departLng REAL, arriveeLat REAL, arriveeLng REAL)''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS covoiturage_reservations (
      id TEXT PRIMARY KEY, trajetId TEXT NOT NULL, participantId TEXT NOT NULL,
      participantNom TEXT NOT NULL, placesReservees INTEGER NOT NULL,
      dateCreation TEXT NOT NULL, statut TEXT NOT NULL DEFAULT 'enAttente',
      FOREIGN KEY (trajetId) REFERENCES covoiturage_trajets(id) ON DELETE CASCADE)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS covoiturage_notifications (
      id TEXT PRIMARY KEY, userId TEXT NOT NULL, type TEXT NOT NULL,
      titre TEXT NOT NULL, message TEXT NOT NULL, trajetId TEXT,
      reservationId TEXT, lue INTEGER NOT NULL DEFAULT 0, dateCreation TEXT NOT NULL,
      cleUnique TEXT UNIQUE,
      FOREIGN KEY (trajetId) REFERENCES covoiturage_trajets(id) ON DELETE SET NULL,
      FOREIGN KEY (reservationId) REFERENCES covoiturage_reservations(id) ON DELETE SET NULL)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS covoiturage_evaluations (
      id TEXT PRIMARY KEY, trajetId TEXT NOT NULL, evaluateurId TEXT NOT NULL,
      evalueId TEXT NOT NULL, note INTEGER NOT NULL CHECK(note BETWEEN 1 AND 5),
      commentaire TEXT NOT NULL DEFAULT '', dateCreation TEXT NOT NULL,
      UNIQUE(trajetId, evaluateurId, evalueId),
      FOREIGN KEY (trajetId) REFERENCES covoiturage_trajets(id) ON DELETE CASCADE)''',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS covoiturage_zones (
      userId TEXT PRIMARY KEY, zone TEXT NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS covoiturage_trajets_date ON covoiturage_trajets(date, heure)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS covoiturage_reservations_trajet ON covoiturage_reservations(trajetId, statut)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS covoiturage_notifications_user ON covoiturage_notifications(userId, lue, dateCreation DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS covoiturage_evaluations_user ON covoiturage_evaluations(evalueId)',
    );
  }

  Future<void> _creerTableAlertesTrajet(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS alertes_trajet (
      id TEXT PRIMARY KEY, userId TEXT NOT NULL, depart TEXT NOT NULL,
      arrivee TEXT NOT NULL, zone TEXT NOT NULL, departLat REAL, departLng REAL,
      arriveeLat REAL, arriveeLng REAL, typeCible TEXT NOT NULL,
      creneau TEXT NOT NULL, jours TEXT NOT NULL DEFAULT '', places INTEGER NOT NULL,
      prixMax REAL, active INTEGER NOT NULL DEFAULT 1, dateCreation TEXT NOT NULL)''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS alertes_trajet_user ON alertes_trajet(userId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS alertes_trajet_zone ON alertes_trajet(zone)',
    );
  }

  Future<void> _createHousingTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS visit_availability (
      id TEXT PRIMARY KEY, ownerId TEXT NOT NULL, startDate TEXT NOT NULL,
      endDate TEXT NOT NULL, startTime TEXT NOT NULL, endTime TEXT NOT NULL,
      durationMinutes INTEGER NOT NULL, breakMinutes INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS visits (
      id TEXT PRIMARY KEY, availabilityId TEXT NOT NULL, ownerId TEXT NOT NULL,
      clientId TEXT NOT NULL, propertyId TEXT NOT NULL, startAt TEXT NOT NULL,
      endAt TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'confirmed')''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS visits_owner_start ON visits(ownerId, startAt)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS rental_requests (
      id TEXT PRIMARY KEY, ownerId TEXT NOT NULL, clientId TEXT NOT NULL,
      propertyId TEXT NOT NULL, visitId TEXT, monthlyRent REAL NOT NULL,
      propertyType TEXT NOT NULL, startDate TEXT NOT NULL, endDate TEXT NOT NULL,
      duration INTEGER NOT NULL, paymentFrequency TEXT NOT NULL,
      paymentMethod TEXT NOT NULL, additionalMessage TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending', createdAt TEXT NOT NULL)''');
  }

  Future<void> fermer() async {
    final opening = _opening;
    if (opening == null) return;
    final db = await opening;
    await db.close();
    _opening = null;
  }
}
