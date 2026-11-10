import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studenthub/models/demande_maintenance.dart';
import 'package:studenthub/models/logement_loue.dart';
import 'package:studenthub/models/user_model.dart';
import 'package:studenthub/providers/demande_provider.dart';
import 'package:studenthub/screens/maintenance/demande_form_screen.dart';
import 'package:studenthub/services/database_helper.dart';
import 'package:studenthub/services/demande_permissions.dart';
import 'package:studenthub/services/demande_service.dart';
import 'package:studenthub/services/housing_service.dart';
import 'package:studenthub/services/logement_loue_service.dart';

const _locataire = 'locataire';
const _autreLocataire = 'autre_locataire';
const _prestataire = 'prestataire';
const _autrePrestataire = 'autre_prestataire';
const _proprietaire = 'proprietaire';
const _admin = 'admin';
const _logement = 'annonce_1';
const _logement2 = 'annonce_2';

Future<void> _location(
  Database db,
  String userId,
  String annonceId, {
  String fin = '2099-12-31',
}) => db.insert('logements_loues', {
  'userId': userId,
  'annonceId': annonceId,
  'titre': 'Studio $annonceId',
  'adresse': '12 rue X, Tunis',
  'proprietaireId': _proprietaire,
  'proprietaireNom': 'Sami Ben',
  'debut': '2026-01-01',
  'fin': fin,
});

DemandeLogement _reponseServeur(
  String annonceId,
  String statut, {
  String fin = '2099-12-31',
}) => DemandeLogement({
  'id': 'r_$annonceId',
  'propertyId': annonceId,
  'ownerId': _proprietaire,
  'status': statut,
  'annonceTitre': 'Studio $annonceId',
  'proprietaireNom': 'Sami Ben',
  'logementAdresse': '12 rue X, Tunis',
  'startDate': '2026-01-01',
  'endDate': fin,
});

class _Housing extends HousingService {
  List<DemandeLogement> demandes = const [];
  bool panne = false;

  @override
  Future<({List<DemandeLogement> recues, List<DemandeLogement> envoyees})>
  demandesLocation() async {
    if (panne) throw Exception('hors ligne');
    return (recues: const <DemandeLogement>[], envoyees: demandes);
  }
}

DemandeMaintenance _demande({
  String id = '',
  String userId = '',
  String title = 'Fuite cuisine',
  String? photo,
  String? assigneeId,
  String? logementId = _logement,
  StatutMaintenance statut = StatutMaintenance.enAttente,
}) => DemandeMaintenance(
  id: id,
  userId: userId,
  assigneeId: assigneeId,
  logementId: logementId,
  category: 'plomberie',
  room: 'cuisine',
  urgency: 'moyenne',
  title: title,
  description: 'Une description assez longue',
  residentName: 'Sami Ben',
  residentPhone: '12345678',
  photoPath: photo,
  statut: statut,
  createdAt: DateTime(2026, 11, 1),
);

Future<void> _utilisateur(
  Database db,
  String id,
  UserRole role, {
  int isRemote = 0,
  AccountStatus statut = AccountStatus.approved,
}) => db.insert('users', {
  'id': id,
  'nom': 'Nom',
  'prenom': id,
  'email': '$id@test.local',
  'telephone': 'tel-$id',
  'rolePrincipal': role.name,
  'passwordHash': 'x',
  'passwordSalt': 'x',
  'createdAt': '2026-01-01T00:00:00.000',
  'emailVerified': 1,
  'accountStatus': statut.name,
  'isRemote': isRemote,
});

final Matcher _refuse = throwsA(isA<DemandeAccesRefuse>());

void main() {
  late Directory dossier;
  late DatabaseHelper base;
  late Database db;
  late DemandeService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('demande_roles');
    base = DatabaseHelper.forTests(path: p.join(dossier.path, 'studenthub.db'));
    db = await base.database;
    await _utilisateur(db, _locataire, UserRole.locataire);
    await _utilisateur(db, _autreLocataire, UserRole.locataire);
    await _utilisateur(db, _prestataire, UserRole.prestataire);
    await _utilisateur(db, _autrePrestataire, UserRole.prestataire);
    await _utilisateur(db, _proprietaire, UserRole.proprietaire);
    await _utilisateur(db, _admin, UserRole.administrateur);
    await _location(db, _locataire, _logement);
    await _location(db, _autreLocataire, _logement2);
    service = DemandeService(
      database: base,
      dossierDocuments: () async => dossier,
    );
  });

  tearDown(() async {
    await base.fermer();
    await dossier.delete(recursive: true);
  });

  /// Crée une demande du locataire et rend son identifiant.
  Future<String> creer({String acteur = _locataire}) async {
    await service.ajouter(acteur, _demande());
    return (await service.lister(acteur)).first.id;
  }

  Future<DemandeMaintenance> lire(String id) async =>
      (await service.lister(_proprietaire)).firstWhere((d) => d.id == id);

  Future<String> assignee() async {
    final id = await creer();
    await service.assigner(_proprietaire, id, _prestataire);
    return id;
  }

  Future<String> terminee() async {
    final id = await creer();
    await service.changerStatut(_locataire, id, StatutMaintenance.terminee);
    return id;
  }

  group('base de données', () {
    test('migration de la version 16 vers la dernière sans perte', () async {
      final chemin = p.join(dossier.path, 'ancienne.db');
      final ancienne = await openDatabase(
        chemin,
        version: 16,
        onCreate: (d, _) async {
          await d.execute('CREATE TABLE users (id TEXT PRIMARY KEY)');
          await d.insert('users', {'id': 'u1'});
        },
      );
      await ancienne.close();

      final helper = DatabaseHelper.forTests(path: chemin);
      final migree = await helper.database;
      expect(await migree.getVersion(), DatabaseHelper.versionSchema);
      expect(await migree.query('users'), hasLength(1));
      final objets = await migree.query(
        'sqlite_master',
        columns: ['name'],
        where: "name LIKE 'demande%'",
      );
      expect(
        objets.map((o) => o['name']),
        containsAll([
          'demandes',
          'demande_historique',
          'demandes_user',
          'demandes_assignee',
          'demande_historique_demande',
        ]),
      );
      await helper.fermer();
    });

    test('une base neuve contient les tables', () async {
      expect(await db.getVersion(), DatabaseHelper.versionSchema);
      expect(await db.query('demandes'), isEmpty);
      expect(await db.query('demande_historique'), isEmpty);
    });

    test('supprimer l’auteur supprime ses demandes et leur historique', () async {
      await creer();
      await db.delete('users', where: 'id = ?', whereArgs: [_locataire]);
      expect(await db.query('demandes'), isEmpty);
      expect(await db.query('demande_historique'), isEmpty);
    });

    test('supprimer le prestataire met assigneeId à null', () async {
      final id = await assignee();
      await db.delete('users', where: 'id = ?', whereArgs: [_prestataire]);
      final demande = await lire(id);
      expect(demande.assigneeId, isNull);
      expect(demande.assigneeNom, isNull);
    });
  });

  group('lecture', () {
    test('chaque rôle voit seulement ce qui le concerne', () async {
      final id = await assignee();
      expect((await service.lister(_locataire)).single.id, id);
      expect(await service.lister(_autreLocataire), isEmpty);
      expect((await service.lister(_prestataire)).single.id, id);
      expect(await service.lister(_autrePrestataire), isEmpty);
      expect((await service.lister(_proprietaire)).single.id, id);
      expect((await service.lister(_admin)).single.id, id);
    });

    test('le nom du prestataire est lu, jamais écrit', () async {
      final id = await assignee();
      expect((await lire(id)).assigneeNom, '$_prestataire Nom');
      expect(_demande().toJson().containsKey('assigneeNom'), isFalse);
      final colonnes = await db.rawQuery('PRAGMA table_info(demandes)');
      expect(colonnes.map((c) => c['name']), isNot(contains('assigneeNom')));
    });

    test('utilisateur introuvable : tout est refusé', () async {
      final id = await creer();
      const inconnu = 'inconnu';
      await expectLater(service.lister(inconnu), _refuse);
      await expectLater(service.ajouter(inconnu, _demande()), _refuse);
      await expectLater(
        service.modifier(inconnu, _demande(id: id)),
        _refuse,
      );
      await expectLater(service.supprimer(inconnu, id), _refuse);
      await expectLater(
        service.changerStatut(inconnu, id, StatutMaintenance.enCours),
        _refuse,
      );
      await expectLater(service.assigner(inconnu, id, null), _refuse);
      await expectLater(service.listerPrestataires(inconnu), _refuse);
      await expectLater(service.historique(inconnu, id), _refuse);
    });
  });

  group('création', () {
    test('seul le locataire crée', () async {
      for (final acteur in [_prestataire, _proprietaire, _admin]) {
        await expectLater(service.ajouter(acteur, _demande()), _refuse);
      }
      expect(await db.query('demandes'), isEmpty);
    });

    test('auteur, statut et assignation sont forcés', () async {
      await service.ajouter(
        _locataire,
        _demande(
          id: 'imposé',
          userId: _autreLocataire,
          assigneeId: _prestataire,
          statut: StatutMaintenance.terminee,
        ),
      );
      final demande = (await service.lister(_locataire)).single;
      expect(demande.id, isNot('imposé'));
      expect(demande.userId, _locataire);
      expect(demande.assigneeId, isNull);
      expect(demande.statut, StatutMaintenance.enAttente);
    });

    test('si l’insertion échoue, la photo copiée est supprimée', () async {
      final source = File(p.join(dossier.path, 'galerie.jpg'));
      await source.writeAsBytes([1, 2, 3]);
      await db.execute(
        'CREATE TRIGGER echec BEFORE INSERT ON demande_historique '
        "BEGIN SELECT RAISE(ABORT, 'echec'); END",
      );
      await expectLater(
        service.ajouter(_locataire, _demande(photo: source.path)),
        throwsA(anything),
      );
      expect(await db.query('demandes'), isEmpty, reason: 'transaction');
      final copies = Directory(p.join(dossier.path, 'maintenance_photos'));
      expect(copies.listSync(), isEmpty);
      expect(source.existsSync(), isTrue);
    });
  });

  group('modification', () {
    test('le locataire auteur modifie le contenu', () async {
      final id = await creer();
      await service.modifier(
        _locataire,
        (await lire(id)).copyWith(title: 'Nouveau titre'),
      );
      expect((await lire(id)).title, 'Nouveau titre');
    });

    test('les autres rôles ne modifient pas', () async {
      final id = await assignee();
      final demande = await lire(id);
      for (final acteur in [
        _autreLocataire,
        _prestataire,
        _proprietaire,
        _admin,
      ]) {
        await expectLater(service.modifier(acteur, demande), _refuse);
      }
    });

    test('impossible de changer statut, assignation, auteur ou date', () async {
      final id = await creer();
      final avant = await lire(id);
      await service.modifier(
        _locataire,
        avant.copyWith(
          title: 'Autre titre',
          statut: StatutMaintenance.terminee,
          assigneeId: _prestataire,
          userId: _autreLocataire,
          createdAt: DateTime(2000),
        ),
      );
      final apres = await lire(id);
      expect(apres.title, 'Autre titre');
      expect(apres.statut, StatutMaintenance.enAttente);
      expect(apres.assigneeId, isNull);
      expect(apres.userId, _locataire);
      expect(apres.createdAt, avant.createdAt);
    });

    test('demande introuvable', () async {
      await expectLater(
        service.modifier(_locataire, _demande(id: 'x')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Demande introuvable: x',
          ),
        ),
      );
    });

    test('une demande terminée n’est plus modifiable', () async {
      final id = await terminee();
      await expectLater(
        service.modifier(_locataire, await lire(id)),
        _refuse,
      );
    });

    test('changer de photo remplace le fichier, sans toucher la galerie', () async {
      final source1 = File(p.join(dossier.path, 'a.jpg'));
      final source2 = File(p.join(dossier.path, 'b.jpg'));
      await source1.writeAsBytes([1]);
      await source2.writeAsBytes([2]);
      await service.ajouter(_locataire, _demande(photo: source1.path));
      final demande = (await service.lister(_locataire)).single;
      final copie1 = demande.photoPath!;
      expect(copie1, contains('maintenance_photos'));
      await service.modifier(
        _locataire,
        demande.copyWith(photoPath: source2.path),
      );
      expect(File(copie1).existsSync(), isFalse);
      expect(source1.existsSync(), isTrue);
      expect(source2.existsSync(), isTrue);
    });
  });

  group('suppression', () {
    test('auteur, propriétaire et administrateur suppriment', () async {
      for (final acteur in [_locataire, _proprietaire, _admin]) {
        final id = await creer();
        await service.supprimer(acteur, id);
        expect(await db.query('demandes'), isEmpty, reason: acteur);
      }
    });

    test('l’auteur supprime aussi une demande terminée', () async {
      await service.supprimer(_locataire, await terminee());
      expect(await db.query('demandes'), isEmpty);
    });

    test('un autre locataire et le prestataire sont refusés', () async {
      final id = await assignee();
      await expectLater(service.supprimer(_autreLocataire, id), _refuse);
      await expectLater(service.supprimer(_prestataire, id), _refuse);
      expect(await db.query('demandes'), hasLength(1));
    });

    test('la photo est supprimée avec la demande', () async {
      final source = File(p.join(dossier.path, 'a.jpg'));
      await source.writeAsBytes([1]);
      await service.ajouter(_locataire, _demande(photo: source.path));
      final demande = (await service.lister(_locataire)).single;
      await service.supprimer(_locataire, demande.id);
      expect(File(demande.photoPath!).existsSync(), isFalse);
      expect(source.existsSync(), isTrue);
    });
  });

  group('statut', () {
    test('le locataire auteur marque résolue, rien d’autre', () async {
      final id = await creer();
      await expectLater(
        service.changerStatut(_locataire, id, StatutMaintenance.enCours),
        _refuse,
      );
      await service.changerStatut(_locataire, id, StatutMaintenance.terminee);
      expect((await lire(id)).statut, StatutMaintenance.terminee);
    });

    test('un autre locataire est refusé', () async {
      final id = await creer();
      await expectLater(
        service.changerStatut(_autreLocataire, id, StatutMaintenance.terminee),
        _refuse,
      );
    });

    test('le prestataire assigné passe en cours puis terminée', () async {
      final id = await assignee();
      await expectLater(
        service.changerStatut(_prestataire, id, StatutMaintenance.enAttente),
        _refuse,
      );
      await service.changerStatut(_prestataire, id, StatutMaintenance.enCours);
      expect((await lire(id)).statut, StatutMaintenance.enCours);
      await service.changerStatut(_prestataire, id, StatutMaintenance.terminee);
      expect((await lire(id)).statut, StatutMaintenance.terminee);
      await expectLater(
        service.changerStatut(_prestataire, id, StatutMaintenance.enCours),
        _refuse,
      );
    });

    test('un prestataire non assigné est refusé', () async {
      final id = await assignee();
      await expectLater(
        service.changerStatut(
          _autrePrestataire,
          id,
          StatutMaintenance.enCours,
        ),
        _refuse,
      );
    });

    test('réouverture réservée au propriétaire et à l’administrateur', () async {
      final id = await terminee();
      await expectLater(
        service.changerStatut(_locataire, id, StatutMaintenance.enCours),
        _refuse,
      );
      await service.changerStatut(_proprietaire, id, StatutMaintenance.enAttente);
      expect((await lire(id)).statut, StatutMaintenance.enAttente);
      await service.changerStatut(_admin, id, StatutMaintenance.terminee);
      await service.changerStatut(_admin, id, StatutMaintenance.enCours);
      expect((await lire(id)).statut, StatutMaintenance.enCours);
    });
  });

  group('historique', () {
    test('création, changements, et rien si le statut est identique', () async {
      final id = await assignee();
      var lignes = await service.historique(_locataire, id);
      expect(lignes.single.statut, StatutMaintenance.enAttente);
      expect(lignes.single.auteurId, _locataire);

      await service.changerStatut(_prestataire, id, StatutMaintenance.enCours);
      await service.changerStatut(_prestataire, id, StatutMaintenance.enCours);
      await service.changerStatut(_proprietaire, id, StatutMaintenance.terminee);
      lignes = await service.historique(_proprietaire, id);
      expect(lignes.map((l) => l.statut), [
        StatutMaintenance.enAttente,
        StatutMaintenance.enCours,
        StatutMaintenance.terminee,
      ]);
      expect(lignes.map((l) => l.auteurId), [
        _locataire,
        _prestataire,
        _proprietaire,
      ]);
    });

    test('mêmes droits que voir', () async {
      final id = await assignee();
      expect(await service.historique(_prestataire, id), hasLength(1));
      await expectLater(service.historique(_autreLocataire, id), _refuse);
      await expectLater(service.historique(_autrePrestataire, id), _refuse);
    });

    test('un changement raté n’écrit pas d’historique', () async {
      final id = await creer();
      await db.execute(
        'CREATE TRIGGER echec BEFORE INSERT ON demande_historique '
        "BEGIN SELECT RAISE(ABORT, 'echec'); END",
      );
      await expectLater(
        service.changerStatut(_proprietaire, id, StatutMaintenance.enCours),
        throwsA(anything),
      );
      expect((await lire(id)).statut, StatutMaintenance.enAttente);
    });
  });

  group('assignation', () {
    test('propriétaire et administrateur assignent et retirent', () async {
      for (final acteur in [_proprietaire, _admin]) {
        final id = await creer();
        await service.assigner(acteur, id, _prestataire);
        expect((await lire(id)).assigneeId, _prestataire);
        await service.assigner(acteur, id, null);
        expect((await lire(id)).assigneeId, isNull);
      }
    });

    test('locataire et prestataire sont refusés', () async {
      final id = await creer();
      await expectLater(service.assigner(_locataire, id, _prestataire), _refuse);
      await expectLater(
        service.assigner(_prestataire, id, _prestataire),
        _refuse,
      );
    });

    test('demande terminée : assignation refusée', () async {
      await expectLater(
        service.assigner(_proprietaire, await terminee(), _prestataire),
        _refuse,
      );
    });

    test('cible invalide refusée', () async {
      await _utilisateur(
        db,
        'bloque',
        UserRole.prestataire,
        statut: AccountStatus.blocked,
      );
      await _utilisateur(db, 'distant', UserRole.prestataire, isRemote: 1);
      final id = await creer();
      for (final cible in [_locataire, _proprietaire, 'bloque', 'distant', 'x']) {
        await expectLater(
          service.assigner(_proprietaire, id, cible),
          _refuse,
          reason: cible,
        );
      }
      expect((await lire(id)).assigneeId, isNull);
    });

    test('liste des prestataires : gestionnaires seulement, comptes valides', () async {
      await _utilisateur(
        db,
        'bloque',
        UserRole.prestataire,
        statut: AccountStatus.blocked,
      );
      await _utilisateur(db, 'distant', UserRole.prestataire, isRemote: 1);
      final liste = await service.listerPrestataires(_proprietaire);
      expect(liste.map((e) => e.id), [_autrePrestataire, _prestataire]);
      expect(await service.listerPrestataires(_admin), hasLength(2));
      await expectLater(service.listerPrestataires(_locataire), _refuse);
      await expectLater(service.listerPrestataires(_prestataire), _refuse);
    });
  });

  group('logements loués', () {
    test('migration 17 vers 18 : colonnes ajoutées, demandes conservées', () async {
      final chemin = p.join(dossier.path, 'v17.db');
      final ancienne = await openDatabase(
        chemin,
        version: 17,
        onCreate: (d, _) async {
          await d.execute('CREATE TABLE users (id TEXT PRIMARY KEY)');
          await d.execute('CREATE TABLE demandes (id TEXT PRIMARY KEY)');
          await d.insert('demandes', {'id': 'd1'});
        },
      );
      await ancienne.close();
      final helper = DatabaseHelper.forTests(path: chemin);
      final migree = await helper.database;
      expect(await migree.query('demandes'), hasLength(1));
      final colonnes = await migree.rawQuery('PRAGMA table_info(demandes)');
      expect(
        colonnes.map((c) => c['name']),
        containsAll([
          'logementId',
          'logementTitre',
          'proprietaireId',
          'proprietaireNom',
        ]),
      );
      expect(await migree.query('logements_loues'), isEmpty);
      await helper.fermer();
    });

    test('la demande est rattachée au logement et à son propriétaire', () async {
      await service.ajouter(_locataire, _demande());
      final demande = (await service.lister(_locataire)).single;
      expect(demande.logementId, _logement);
      expect(demande.logementTitre, 'Studio $_logement');
      expect(demande.proprietaireId, _proprietaire);
      expect(demande.proprietaireNom, 'Sami Ben');
    });

    test('le nom du propriétaire ne peut pas être imposé', () async {
      await service.ajouter(
        _locataire,
        _demande().copyWith(proprietaireNom: 'Faux nom'),
      );
      final demande = (await service.lister(_locataire)).single;
      expect(demande.proprietaireNom, 'Sami Ben');
    });

    test('téléphone du profil : 8 chiffres après +216 ou 00216', () {
      const cas = {
        '+216 50 777 888': '50777888',
        '0021650777888': '50777888',
        '21650777888': '50777888',
        '50777888': '50777888',
        '21612345': '21612345',
        '+33 6 12 34 56 78': null,
        'a-completer-demo': null,
        '': null,
      };
      cas.forEach((entree, attendu) {
        expect(
          ValidateursDemande.telephoneDepuisProfil(entree),
          attendu,
          reason: entree,
        );
      });
      expect(ValidateursDemande.telephoneDepuisProfil(null), isNull);
    });

    test('création refusée sans logement ou pour le logement d’un autre', () async {
      await expectLater(
        service.ajouter(_locataire, _demande(logementId: null)),
        _refuse,
      );
      await expectLater(
        service.ajouter(_locataire, _demande(logementId: _logement2)),
        _refuse,
      );
      expect(await db.query('demandes'), isEmpty);
    });

    test('location terminée : création refusée', () async {
      await _location(db, _locataire, 'ancienne', fin: '2020-01-01');
      await expectLater(
        service.ajouter(_locataire, _demande(logementId: 'ancienne')),
        _refuse,
      );
    });

    test('changer de logement : seulement vers un logement loué', () async {
      await _location(db, _locataire, 'autre');
      final id = await creer();
      final demande = await lire(id);
      await expectLater(
        service.modifier(_locataire, demande.copyWith(logementId: _logement2)),
        _refuse,
      );
      await service.modifier(_locataire, demande.copyWith(logementId: 'autre'));
      expect((await lire(id)).logementId, 'autre');
      expect((await lire(id)).logementTitre, 'Studio autre');
    });

    test('une demande reste modifiable après la fin de la location', () async {
      final id = await creer();
      await db.update(
        'logements_loues',
        {'fin': '2020-01-01'},
        where: 'annonceId = ?',
        whereArgs: [_logement],
      );
      await service.modifier(
        _locataire,
        (await lire(id)).copyWith(title: 'Titre modifié'),
      );
      expect((await lire(id)).title, 'Titre modifié');
      expect((await lire(id)).logementId, _logement);
    });

    test('synchroniser garde seulement les locations acceptées et en cours', () async {
      final housing = _Housing()
        ..demandes = [
          _reponseServeur('acceptee', 'accepted'),
          _reponseServeur('attente', 'pending'),
          _reponseServeur('refusee', 'refused'),
          _reponseServeur('annulee', 'cancelled'),
          _reponseServeur('echue', 'accepted', fin: '2020-01-01'),
        ];
      final logements = LogementLoueService(database: base, housing: housing);
      await logements.synchroniser(_locataire);
      final List<LogementLoue> liste = await logements.lister(_locataire);
      expect(liste.map((l) => l.annonceId), ['acceptee']);
      expect(liste.single.adresse, '12 rue X, Tunis');
    });

    test('hors ligne : la copie locale est conservée', () async {
      final logements = LogementLoueService(
        database: base,
        housing: _Housing()..panne = true,
      );
      await expectLater(logements.synchroniser(_locataire), throwsA(anything));
      expect(await logements.lister(_locataire), hasLength(1));
    });

    test('supprimer le compte supprime ses logements', () async {
      await db.delete('users', where: 'id = ?', whereArgs: [_locataire]);
      expect(
        await db.query(
          'logements_loues',
          where: 'userId = ?',
          whereArgs: [_locataire],
        ),
        isEmpty,
      );
    });
  });

  group('DemandePermissions', () {
    final d = _demande(id: '1', userId: 'moi', assigneeId: 'presta');

    test('rôle secondaire sans effet : seul le rôle principal compte', () {
      expect(DemandePermissions.creer(UserRole.proprietaire), isFalse);
    });

    test('statuts proposés', () {
      expect(
        DemandePermissions.statutsAutorises(UserRole.locataire, 'moi', d),
        isEmpty,
      );
      expect(
        DemandePermissions.statutsAutorises(UserRole.prestataire, 'presta', d),
        [StatutMaintenance.enCours, StatutMaintenance.terminee],
      );
      expect(
        DemandePermissions.statutsAutorises(UserRole.prestataire, 'autre', d),
        isEmpty,
      );
      expect(
        DemandePermissions.statutsAutorises(UserRole.proprietaire, 'p', d),
        StatutMaintenance.values,
      );
    });
  });

  group('DemandeProvider', () {
    late DemandeProvider provider;

    setUp(() {
      provider = DemandeProvider(
        service: service,
        logements: LogementLoueService(
          database: base,
          housing: _Housing()..panne = true,
        ),
      );
    });
    tearDown(() => provider.dispose());

    /// Laisse le microtask et les accès base se terminer.
    Future<void> attendre() async {
      await Future<void>.delayed(Duration.zero);
      while (provider.chargement) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('charger ne lit rien sans utilisateur', () async {
      await creer();
      await provider.charger();
      expect(provider.demandes, isEmpty);
      expect(provider.role, isNull);
    });

    test('aucune notification pendant l’appel de definirUtilisateur', () async {
      var notifications = 0;
      provider.addListener(() => notifications++);
      provider.definirUtilisateur(_locataire);
      expect(notifications, 0);
      await attendre();
      expect(notifications, greaterThan(0));
    });

    test('recharge au changement de compte, vide à la déconnexion', () async {
      await creer();
      provider.definirUtilisateur(_locataire);
      await attendre();
      expect(provider.demandes, hasLength(1));
      expect(provider.role, UserRole.locataire);
      expect(provider.peutCreer, isTrue);

      provider.definirUtilisateur(_autreLocataire);
      expect(provider.demandes, isEmpty, reason: 'pas de fuite entre comptes');
      await attendre();
      expect(provider.demandes, isEmpty);

      provider.definirUtilisateur(_proprietaire);
      await attendre();
      expect(provider.demandes, hasLength(1));
      expect(provider.role, UserRole.proprietaire);
      expect(provider.peutCreer, isFalse);

      provider
        ..setRecherche('fuite')
        ..setFiltreUrgence('moyenne')
        ..definirUtilisateur(null);
      await attendre();
      expect(provider.demandes, isEmpty);
      expect(provider.role, isNull);
      expect(provider.recherche, isEmpty);
      expect(provider.nombreFiltresActifs, 0);
    });

    test('même identifiant : aucun rechargement', () async {
      provider.definirUtilisateur(_locataire);
      await attendre();
      // Les logements se chargent après les demandes, sans bloquer `chargement`.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      var notifications = 0;
      provider.addListener(() => notifications++);
      provider.definirUtilisateur(_locataire);
      await attendre();
      expect(notifications, 0);
    });

    test('droits exposés et actions refusées', () async {
      final id = await assignee();
      provider.definirUtilisateur(_prestataire);
      await attendre();
      final demande = provider.demandes.single;
      expect(provider.peutModifier(demande), isFalse);
      expect(provider.peutSupprimer(demande), isFalse);
      expect(provider.peutMarquerResolue(demande), isFalse);
      expect(provider.peutAssigner(demande), isFalse);
      expect(provider.statutsAutorises(demande), hasLength(2));
      await expectLater(provider.supprimer(id), _refuse);
      await provider.changerStatut(id, StatutMaintenance.enCours);
      expect(provider.demandes.single.statut, StatutMaintenance.enCours);
    });

    test('le provider expose les logements du locataire seulement', () async {
      await creer();
      provider.definirUtilisateur(_locataire);
      await attendre();
      await provider.chargerLogements();
      expect(provider.logements.single.annonceId, _logement);
      expect(provider.demandesDuLogement(_logement), 1);

      provider.definirUtilisateur(_proprietaire);
      expect(provider.logements, isEmpty);
      await attendre();
      await provider.chargerLogements();
      expect(provider.logements, isEmpty);
    });

    test('sans session : action refusée', () {
      expect(
        () => provider.changerStatut('x', StatutMaintenance.enCours),
        _refuse,
      );
    });
  });
}
