import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../models/covoiturage_trajet.dart';
import '../models/enums_covoiturage.dart';
import '../models/reservation_trajet.dart';
import 'covoiturage_rules.dart';
import 'database_helper.dart';
import 'notification_covoiturage_service.dart';
import 'alerte_trajet_service.dart';
import 'covoiturage_alertes.dart';

class CompteCovoiturage {
  const CompteCovoiturage(this.id, this.nom, this.zone);
  final String id, nom, zone;
}

class CovoiturageService {
  CovoiturageService({
    DatabaseHelper? database,
    NotificationCovoiturageService? notifications,
    AlerteTrajetService? alertes,
  }) : _database = database ?? DatabaseHelper.instance,
       _notifications = notifications ?? NotificationCovoiturageService(),
       _alertes = alertes ?? AlerteTrajetService();
  final DatabaseHelper _database;
  final NotificationCovoiturageService _notifications;
  final AlerteTrajetService _alertes;
  String _id(String p) =>
      '${p}_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  /// Supprime les anciennes données de démonstration installées par les versions
  /// précédentes et laisse la base contenir uniquement les vraies publications.
  Future<void> initialiser() async {
    final db = await _database.database;
    await db.delete('covoiturage_trajets', where: "id LIKE 'exemple_%'");
    await db.delete('covoiturage_zones', where: "userId LIKE 'covo_demo_%'");
    await db.delete('users', where: "id LIKE 'covo_demo_%'");
  }

  Future<CompteCovoiturage?> compteUtilisateur(String userId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT u.id, u.prenom, u.nom, COALESCE(z.zone, \'Tunis\') zone '
      'FROM users u LEFT JOIN covoiturage_zones z ON z.userId = u.id '
      'WHERE u.id = ?',
      [userId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CompteCovoiturage(
      row['id']! as String,
      '${row['prenom']} ${row['nom']}',
      row['zone']! as String,
    );
  }

  Future<String> zone(String userId) async {
    final db = await _database.database;
    final row = (await db.query(
      'covoiturage_zones',
      where: 'userId = ?',
      whereArgs: [userId],
      limit: 1,
    ));
    return row.isEmpty ? 'Tunis' : row.first['zone']! as String;
  }

  Future<void> definirZone(String userId, String zone) async {
    final db = await _database.database;
    await db.insert('covoiturage_zones', {
      'userId': userId,
      'zone': zone,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<CovoiturageTrajet>> trajets({
    TypeTrajetEnum? type,
    String? auteurId,
  }) async {
    final db = await _database.database;
    final where = <String>[];
    final args = <Object?>[];
    if (type != null) {
      where.add('type = ?');
      args.add(type.name);
    }
    if (auteurId != null) {
      where.add('auteurId = ?');
      args.add(auteurId);
    }
    final rows = await db.query(
      'covoiturage_trajets',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'date ASC, heure ASC',
    );
    return rows.map(CovoiturageTrajet.fromMap).toList();
  }

  Future<CovoiturageTrajet?> trajet(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      'covoiturage_trajets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : CovoiturageTrajet.fromMap(rows.first);
  }

  Future<List<ReservationTrajet>> reservations(String trajetId) async {
    final db = await _database.database;
    final rows = await db.query(
      'covoiturage_reservations',
      where: 'trajetId = ?',
      whereArgs: [trajetId],
      orderBy: 'dateCreation DESC',
    );
    return rows.map(ReservationTrajet.fromMap).toList();
  }

  Future<List<ReservationTrajet>> mesReservations(String userId) async {
    final db = await _database.database;
    final rows = await db.query(
      'covoiturage_reservations',
      where: 'participantId = ?',
      whereArgs: [userId],
      orderBy: 'dateCreation DESC',
    );
    return rows.map(ReservationTrajet.fromMap).toList();
  }

  Future<void> publier(CovoiturageTrajet trajet) async {
    final db = await _database.database;
    if (trajet.type == TypeTrajetEnum.demande && trajet.prix != null)
      throw ArgumentError('Une demande ne comporte pas de prix.');
    await db.insert('covoiturage_trajets', trajet.toMap());
    try {
      await _verifierAlertes(trajet);
    } catch (_) {}
    if (trajet.type == TypeTrajetEnum.demande) {
      final rows = await db.rawQuery(
        'SELECT u.id, COALESCE(z.zone, \'Tunis\') zone FROM users u LEFT JOIN covoiturage_zones z ON z.userId = u.id WHERE u.id != ?',
        [trajet.auteurId],
      );
      for (final row in rows) {
        final id = row['id']! as String;
        if (CovoiturageRules.estDansZone(row['zone'] as String, trajet.zone))
          await _notifications.creer(
            userId: id,
            type: TypeNotificationEnum.nouvelleDemandeZone,
            titre: 'Nouvelle demande dans votre zone',
            message:
                '${trajet.auteurNom} cherche un trajet ${trajet.depart} → ${trajet.arrivee}.',
            trajetId: trajet.id,
          );
      }
    }
  }

  Future<void> modifier(
    CovoiturageTrajet original,
    CovoiturageTrajet nouveau,
  ) async {
    if (!CovoiturageRules.typeModifiable(original, nouveau.type))
      throw StateError('Le type ne peut pas être modifié après publication.');
    if (!CovoiturageRules.peutAnnuler(original, DateTime.now()))
      throw StateError('Le départ est déjà passé.');
    final rs = await reservations(original.id);
    final actives = rs.any(
      (r) =>
          r.statut == StatutReservationEnum.enAttente ||
          r.statut == StatutReservationEnum.confirmee,
    );
    if (actives &&
        (nouveau.depart != original.depart ||
            nouveau.arrivee != original.arrivee ||
            nouveau.date != original.date ||
            nouveau.heure != original.heure))
      throw StateError(
        'Ces informations sont verrouillées car des réservations sont actives.',
      );
    if (nouveau.places < CovoiturageRules.placesConfirmees(rs))
      throw StateError(
        'Le nombre de places est inférieur aux places déjà confirmées.',
      );
    final db = await _database.database;
    await db.update(
      'covoiturage_trajets',
      nouveau.toMap(),
      where: 'id = ?',
      whereArgs: [original.id],
    );
    try {
      await _verifierAlertes(nouveau);
    } catch (_) {}
  }

  /// RG17/RG18 : une notification unique par alerte et publication.
  Future<void> _verifierAlertes(CovoiturageTrajet trajet) async {
    final alertes = await _alertes.activesZone(trajet.zone);
    for (final alerte in alertes) {
      final resultat = CovoiturageAlertes.correspond(
        alerte,
        trajet,
        DateTime.now(),
      );
      if (!resultat.correspond || alerte.userId == trajet.auteurId) continue;
      final type = trajet.type == TypeTrajetEnum.offre
          ? 'une offre'
          : 'une demande';
      final extra = trajet.prix == null
          ? '${trajet.places} place(s)'
          : '${trajet.prix!.toStringAsFixed(1)} TND';
      await _notifications.creer(
        userId: alerte.userId,
        type: TypeNotificationEnum.alerteTrajet,
        titre:
            'Alerte : $type correspond à ${alerte.depart} → ${alerte.arrivee}',
        message: '${trajet.date} à ${trajet.heure} · $extra',
        trajetId: trajet.id,
        cleUnique: 'alerte_${alerte.id}_${trajet.id}_${alerte.userId}',
      );
    }
  }

  Future<void> demander({
    required CovoiturageTrajet trajet,
    required String participantId,
    required String participantNom,
    required int places,
  }) async {
    final rs = await reservations(trajet.id);
    if (!CovoiturageRules.peutReserver(
      trajet: trajet,
      userId: participantId,
      places: places,
      reservations: rs,
    ))
      throw StateError('Cette réservation est impossible.');
    final r = ReservationTrajet(
      id: _id('r'),
      trajetId: trajet.id,
      participantId: participantId,
      participantNom: participantNom,
      placesReservees: trajet.type == TypeTrajetEnum.demande ? 1 : places,
      dateCreation: DateTime.now().toIso8601String(),
    );
    final db = await _database.database;
    await db.insert('covoiturage_reservations', r.toMap());
    await _notifications.creer(
      userId: trajet.auteurId,
      type: trajet.type == TypeTrajetEnum.offre
          ? TypeNotificationEnum.reservationRecue
          : TypeNotificationEnum.propositionRecue,
      titre: trajet.type == TypeTrajetEnum.offre
          ? 'Nouvelle réservation'
          : 'Nouvelle proposition',
      message: '$participantNom a répondu à votre trajet.',
      trajetId: trajet.id,
      reservationId: r.id,
    );
  }

  Future<void> repondre({
    required CovoiturageTrajet trajet,
    required ReservationTrajet reservation,
    required bool accepter,
  }) async {
    if (!CovoiturageRules.peutAnnuler(trajet, DateTime.now()))
      throw StateError('Le départ est déjà passé.');
    final db = await _database.database;
    await db.transaction((txn) async {
      if (accepter && trajet.type == TypeTrajetEnum.demande) {
        final rows = await txn.query(
          'covoiturage_reservations',
          where: 'trajetId = ? AND statut = ?',
          whereArgs: [trajet.id, StatutReservationEnum.enAttente.name],
        );
        for (final row in rows) {
          final other = ReservationTrajet.fromMap(row);
          if (other.id != reservation.id) {
            await txn.update(
              'covoiturage_reservations',
              {'statut': StatutReservationEnum.refusee.name},
              where: 'id = ?',
              whereArgs: [other.id],
            );
            await _notifications.creer(
              userId: other.participantId,
              type: TypeNotificationEnum.refus,
              titre: 'Proposition refusée',
              message: 'Une autre proposition a été retenue.',
              trajetId: trajet.id,
              reservationId: other.id,
            );
          }
        }
      }
      await txn.update(
        'covoiturage_reservations',
        {
          'statut':
              (accepter
                      ? StatutReservationEnum.confirmee
                      : StatutReservationEnum.refusee)
                  .name,
        },
        where: 'id = ?',
        whereArgs: [reservation.id],
      );
      final all = (await txn.query(
        'covoiturage_reservations',
        where: 'trajetId = ?',
        whereArgs: [trajet.id],
      )).map(ReservationTrajet.fromMap).toList();
      final statut = accepter && trajet.type == TypeTrajetEnum.demande
          ? StatutTrajetEnum.complet
          : CovoiturageRules.statutApresReservations(trajet, all);
      await txn.update(
        'covoiturage_trajets',
        {'statut': statut.name},
        where: 'id = ?',
        whereArgs: [trajet.id],
      );
    });
    await _notifications.creer(
      userId: reservation.participantId,
      type: accepter
          ? TypeNotificationEnum.confirmation
          : TypeNotificationEnum.refus,
      titre: accepter ? 'Réservation confirmée' : 'Réservation refusée',
      message:
          'Votre réponse pour ${trajet.depart} → ${trajet.arrivee} a été ${accepter ? 'acceptée' : 'refusée'}.',
      trajetId: trajet.id,
      reservationId: reservation.id,
    );
  }

  Future<void> annulerTrajet(CovoiturageTrajet trajet) async {
    if (!CovoiturageRules.peutAnnuler(trajet, DateTime.now()))
      throw StateError('L’annulation est impossible après le départ.');
    final rs = await reservations(trajet.id);
    final db = await _database.database;
    await db.transaction((t) async {
      await t.update(
        'covoiturage_trajets',
        {'statut': StatutTrajetEnum.annule.name},
        where: 'id = ?',
        whereArgs: [trajet.id],
      );
      await t.update(
        'covoiturage_reservations',
        {'statut': StatutReservationEnum.annulee.name},
        where: 'trajetId = ? AND statut IN (?, ?)',
        whereArgs: [
          trajet.id,
          StatutReservationEnum.enAttente.name,
          StatutReservationEnum.confirmee.name,
        ],
      );
    });
    for (final r in rs.where(
      (r) =>
          r.statut == StatutReservationEnum.enAttente ||
          r.statut == StatutReservationEnum.confirmee,
    )) {
      await _notifications.creer(
        userId: r.participantId,
        type: TypeNotificationEnum.annulation,
        titre: 'Trajet annulé',
        message: 'Le trajet ${trajet.depart} → ${trajet.arrivee} a été annulé.',
        trajetId: trajet.id,
        reservationId: r.id,
      );
    }
  }

  Future<void> annulerReservation(
    CovoiturageTrajet trajet,
    ReservationTrajet reservation,
  ) async {
    if (!CovoiturageRules.peutAnnuler(trajet, DateTime.now()))
      throw StateError('L’annulation est impossible après le départ.');
    final db = await _database.database;
    await db.update(
      'covoiturage_reservations',
      {'statut': StatutReservationEnum.annulee.name},
      where: 'id = ?',
      whereArgs: [reservation.id],
    );
    final rs = await reservations(trajet.id);
    if (trajet.type == TypeTrajetEnum.offre)
      await db.update(
        'covoiturage_trajets',
        {'statut': CovoiturageRules.statutApresReservations(trajet, rs).name},
        where: 'id = ?',
        whereArgs: [trajet.id],
      );
    await _notifications.creer(
      userId: trajet.auteurId,
      type: TypeNotificationEnum.annulation,
      titre: 'Réservation annulée',
      message: '${reservation.participantNom} a annulé sa réservation.',
      trajetId: trajet.id,
      reservationId: reservation.id,
    );
  }

  Future<void> actualiserEtatEtRappels() async {
    final db = await _database.database;
    final list = await trajets();
    final now = DateTime.now();
    for (final trajet in list) {
      if (trajet.statut == StatutTrajetEnum.annule) continue;
      final rs = await reservations(trajet.id);
      if (!now.isBefore(trajet.departAt)) {
        await db.update(
          'covoiturage_trajets',
          {'statut': StatutTrajetEnum.termine.name},
          where: 'id = ?',
          whereArgs: [trajet.id],
        );
        await db.update(
          'covoiturage_reservations',
          {'statut': StatutReservationEnum.annulee.name},
          where: 'trajetId = ? AND statut = ?',
          whereArgs: [trajet.id, StatutReservationEnum.enAttente.name],
        );
      } else if (trajet.departAt.difference(now) <= const Duration(hours: 24)) {
        final ids = <String>{
          trajet.auteurId,
          ...rs
              .where((r) => r.statut == StatutReservationEnum.confirmee)
              .map((r) => r.participantId),
        };
        for (final id in ids) {
          await _notifications.creer(
            userId: id,
            type: TypeNotificationEnum.rappelDepart,
            titre: 'Rappel de départ',
            message:
                'Votre trajet ${trajet.depart} → ${trajet.arrivee} part dans moins de 24 h.',
            trajetId: trajet.id,
            cleUnique: 'rappel_${trajet.id}_$id',
          );
        }
      }
    }
  }
}
