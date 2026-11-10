import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/demande_maintenance.dart';
import '../models/logement_loue.dart';
import '../models/user_model.dart';
import 'database_helper.dart';
import 'demande_permissions.dart';
import 'logement_loue_service.dart';

class DemandeAccesRefuse implements Exception {
  const DemandeAccesRefuse([
    this.message = "Vous n'avez pas le droit d'effectuer cette action.",
  ]);

  final String message;

  @override
  String toString() => message;
}

class PrestataireDemande {
  const PrestataireDemande({required this.id, required this.nom});

  final String id;
  final String nom;
}

/// Toutes les règles sont vérifiées ici, à partir du rôle relu en base :
/// un rôle transmis par l'écran n'est jamais pris en compte.
class DemandeService {
  DemandeService({
    DatabaseHelper? database,
    Future<Directory> Function()? dossierDocuments,
  }) : _database = database ?? DatabaseHelper.instance,
       _dossierDocuments =
           dossierDocuments ?? getApplicationDocumentsDirectory;

  static const _dossierPhotos = 'maintenance_photos';
  static const _table = 'demandes';
  static const _tableHistorique = 'demande_historique';

  final DatabaseHelper _database;
  final Future<Directory> Function() _dossierDocuments;

  Future<UserRole> roleDe(String acteurId) async =>
      _role(await _database.database, acteurId);

  Future<UserRole> _role(DatabaseExecutor db, String acteurId) async {
    final lignes = await db.query(
      'users',
      columns: ['rolePrincipal'],
      where: 'id = ?',
      whereArgs: [acteurId],
      limit: 1,
    );
    final nom = lignes.isEmpty ? null : lignes.first['rolePrincipal'];
    for (final role in UserRole.values) {
      if (role.name == nom) return role;
    }
    throw const DemandeAccesRefuse();
  }

  Future<DemandeMaintenance?> _lire(DatabaseExecutor db, String id) async {
    final lignes = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return lignes.isEmpty ? null : DemandeMaintenance.fromJson(lignes.first);
  }

  Future<DemandeMaintenance> _exiger(DatabaseExecutor db, String id) async {
    final demande = await _lire(db, id);
    if (demande == null) throw StateError('Demande introuvable: $id');
    return demande;
  }

  void _verifier(bool autorise) {
    if (!autorise) throw const DemandeAccesRefuse();
  }

  /// Logement actuellement loué par [acteurId], ou refus.
  Future<LogementLoue> _logementLoue(
    DatabaseExecutor db,
    String acteurId,
    String? logementId,
  ) async {
    final lignes = await db.query(
      'logements_loues',
      where: 'userId = ? AND annonceId = ? AND fin >= ?',
      whereArgs: [acteurId, logementId, jourCourant()],
      limit: 1,
    );
    if (lignes.isEmpty) {
      throw const DemandeAccesRefuse(
        'Choisissez un logement que vous louez actuellement.',
      );
    }
    return LogementLoue.fromJson(lignes.first);
  }

  Future<void> _historiser(
    DatabaseExecutor db,
    String demandeId,
    StatutMaintenance statut,
    String auteurId,
  ) => db.insert(_tableHistorique, {
    'demandeId': demandeId,
    'statut': statut.name,
    'date': DateTime.now().toIso8601String(),
    'auteurId': auteurId,
  });

  Future<List<DemandeMaintenance>> lister(String acteurId) async {
    final db = await _database.database;
    final role = await _role(db, acteurId);
    final lignes = await db.rawQuery('''
      SELECT d.*, TRIM(u.prenom || ' ' || u.nom) AS assigneeNom
      FROM $_table d LEFT JOIN users u ON u.id = d.assigneeId
      ORDER BY d.createdAt DESC
    ''');
    return lignes
        .map(DemandeMaintenance.fromJson)
        .where((d) => DemandePermissions.voir(role, acteurId, d))
        .toList();
  }

  Future<void> ajouter(String acteurId, DemandeMaintenance demande) async {
    final db = await _database.database;
    _verifier(DemandePermissions.creer(await _role(db, acteurId)));
    final logement = await _logementLoue(db, acteurId, demande.logementId);
    final photo = await _copierPhoto(demande.photoPath);
    final nouvelle = demande.copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      userId: acteurId,
      assigneeId: null,
      logementId: logement.annonceId,
      logementTitre: logement.titre,
      proprietaireId: logement.proprietaireId,
      proprietaireNom: logement.proprietaireNom,
      statut: StatutMaintenance.enAttente,
      photoPath: photo,
    );
    try {
      await db.transaction((txn) async {
        await txn.insert(_table, nouvelle.toJson());
        await _historiser(
          txn,
          nouvelle.id,
          StatutMaintenance.enAttente,
          acteurId,
        );
      });
    } catch (_) {
      await _supprimerFichier(photo);
      rethrow;
    }
  }

  Future<void> modifier(String acteurId, DemandeMaintenance demande) async {
    final db = await _database.database;
    final role = await _role(db, acteurId);
    final ancienne = await _exiger(db, demande.id);
    _verifier(DemandePermissions.modifier(role, acteurId, ancienne));
    // Un changement de logement doit viser un logement loué ; une demande dont
    // la location s'est terminée garde simplement son logement d'origine.
    final nouveauLogement = demande.logementId == ancienne.logementId
        ? null
        : await _logementLoue(db, acteurId, demande.logementId);
    final anciennePhoto = ancienne.photoPath;
    final nouvellePhotoCopiee = demande.photoPath != anciennePhoto;
    final photo = nouvellePhotoCopiee
        ? await _copierPhoto(demande.photoPath)
        : anciennePhoto;
    try {
      await db.update(
        _table,
        {
          'category': demande.category,
          'room': demande.room,
          'urgency': demande.urgency,
          'title': demande.title,
          'description': demande.description,
          'residentName': demande.residentName,
          'residentPhone': demande.residentPhone,
          'photoPath': photo,
          if (nouveauLogement != null) ...{
            'logementId': nouveauLogement.annonceId,
            'logementTitre': nouveauLogement.titre,
            'proprietaireId': nouveauLogement.proprietaireId,
            'proprietaireNom': nouveauLogement.proprietaireNom,
          },
        },
        where: 'id = ?',
        whereArgs: [demande.id],
      );
    } catch (_) {
      if (nouvellePhotoCopiee) await _supprimerFichier(photo);
      rethrow;
    }
    if (nouvellePhotoCopiee) await _supprimerFichier(anciennePhoto);
  }

  Future<void> supprimer(String acteurId, String id) async {
    final db = await _database.database;
    final role = await _role(db, acteurId);
    final demande = await _lire(db, id);
    if (demande == null) return;
    _verifier(DemandePermissions.supprimer(role, acteurId, demande));
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    await _supprimerFichier(demande.photoPath);
  }

  Future<void> changerStatut(
    String acteurId,
    String id,
    StatutMaintenance statut,
  ) async {
    final db = await _database.database;
    final role = await _role(db, acteurId);
    final demande = await _exiger(db, id);
    _verifier(DemandePermissions.changerStatut(role, acteurId, demande, statut));
    if (demande.statut == statut) return;
    await db.transaction((txn) async {
      await txn.update(
        _table,
        {'statut': statut.name},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _historiser(txn, id, statut, acteurId);
    });
  }

  Future<void> assigner(
    String acteurId,
    String id,
    String? prestataireId,
  ) async {
    final db = await _database.database;
    final role = await _role(db, acteurId);
    final demande = await _exiger(db, id);
    _verifier(DemandePermissions.assigner(role, demande));
    if (prestataireId != null) {
      final cible = await db.query(
        'users',
        columns: ['id'],
        where: 'id = ? AND $_filtrePrestataire',
        whereArgs: [prestataireId, ..._argumentsPrestataire],
        limit: 1,
      );
      _verifier(cible.isNotEmpty);
    }
    await db.update(
      _table,
      {'assigneeId': prestataireId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static const _filtrePrestataire =
      'rolePrincipal = ? AND isRemote = 0 AND accountStatus = ?';
  static final _argumentsPrestataire = [
    UserRole.prestataire.name,
    AccountStatus.approved.name,
  ];

  Future<List<PrestataireDemande>> listerPrestataires(String acteurId) async {
    final db = await _database.database;
    final role = await _role(db, acteurId);
    _verifier(role == UserRole.proprietaire || role == UserRole.administrateur);
    final lignes = await db.query(
      'users',
      columns: ['id', 'prenom', 'nom'],
      where: _filtrePrestataire,
      whereArgs: _argumentsPrestataire,
      orderBy: 'prenom, nom',
    );
    return [
      for (final ligne in lignes)
        PrestataireDemande(
          id: ligne['id']! as String,
          nom: '${ligne['prenom']} ${ligne['nom']}'.trim(),
        ),
    ];
  }

  Future<List<DemandeHistorique>> historique(String acteurId, String id) async {
    final db = await _database.database;
    final role = await _role(db, acteurId);
    final demande = await _exiger(db, id);
    _verifier(DemandePermissions.voir(role, acteurId, demande));
    final lignes = await db.query(
      _tableHistorique,
      where: 'demandeId = ?',
      whereArgs: [id],
      orderBy: 'date ASC, id ASC',
    );
    return lignes.map(DemandeHistorique.fromJson).toList();
  }

  Future<String?> _copierPhoto(String? source) async {
    if (source == null) return null;
    final documents = await _dossierDocuments();
    final dossier = Directory(p.join(documents.path, _dossierPhotos));
    await dossier.create(recursive: true);
    final nom =
        '${DateTime.now().microsecondsSinceEpoch}${p.extension(source)}';
    final copie = await File(source).copy(p.join(dossier.path, nom));
    return copie.path;
  }

  /// Ne touche jamais à un fichier hors du dossier de l'application (galerie).
  Future<void> _supprimerFichier(String? chemin) async {
    if (chemin == null || !chemin.contains(_dossierPhotos)) return;
    final fichier = File(chemin);
    if (await fichier.exists()) await fichier.delete();
  }
}
