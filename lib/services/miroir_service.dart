import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'api_client.dart';
import 'database_helper.dart';

/// Table copiée dans les deux sens. [cle] identifie une ligne sur tous les
/// téléphones ; les colonnes [ignorer] sont propres à chaque appareil.
class TableMiroir {
  const TableMiroir(this.nom, this.cle, {this.ignorer = const []});
  final String nom;
  final List<String> cle;
  final List<String> ignorer;
}

/// Tables écrites sur le téléphone et recopiées en JSON sur le serveur. Les
/// parents précèdent leurs enfants. `users` et `app_settings` n'y figurent pas :
/// mots de passe et jetons ne quittent jamais leur emplacement.
const tablesMiroir = [
  TableMiroir('covoiturage_trajets', ['id']),
  TableMiroir('covoiturage_reservations', ['id']),
  TableMiroir('covoiturage_evaluations', ['id']),
  TableMiroir('covoiturage_notifications', ['id']),
  TableMiroir('covoiturage_zones', ['userId']),
  TableMiroir('alertes_trajet', ['id']),
  TableMiroir('demandes', ['id']),
  TableMiroir('demande_historique', ['demandeId', 'date', 'statut'], ignorer: ['id']),
  TableMiroir('logements_loues', ['userId', 'annonceId']),
  TableMiroir('traductions', ['reponse_id', 'langue'], ignorer: ['id']),
  TableMiroir('trajets', ['depart', 'arrivee', 'mode']),
  TableMiroir('geocodage', ['adresse']),
];

/// Données tenues par le serveur et recopiées dans SQLite.
const tablesServeur = <String, List<String>>{
  'visit_availability': ['id'],
  'visits': ['id'],
  'rental_requests': ['id'],
  'annonce_likes': ['annonceId', 'userId'],
  'annonce_commentaires': ['annonceId', 'userId', 'createdAt'],
  'annonce_avis': ['annonceId', 'userId'],
  'messagerie_conversations': ['id'],
  'messagerie_messages': ['id'],
  'assistant_conversations': ['id'],
};

/// Garde SQLite et les fichiers JSON du serveur identiques, table par table.
class MiroirService {
  MiroirService({ApiClient? client, DatabaseHelper? databaseHelper})
    : _client = client ?? ApiClient(),
      _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  /// Lignes envoyées par requête (le serveur en accepte 100).
  static const tailleLot = 40;

  final ApiClient _client;
  final DatabaseHelper _databaseHelper;
  static Future<int>? _enCours;

  /// Lignes refusées pour ce compte : elles appartiennent souvent à un autre
  /// compte du même téléphone, qui pourra les envoyer quand il se connectera.
  final Map<String, Set<String>> _refusees = {};

  /// Retourne le nombre de lignes modifiées sur ce téléphone. Sans réseau,
  /// l'exception est relancée et les changements attendent la fois suivante.
  Future<int> synchroniser(String userId) {
    final enCours = _enCours;
    if (enCours != null) return enCours;
    final nouveau = _synchroniser(userId).whenComplete(() => _enCours = null);
    _enCours = nouveau;
    return nouveau;
  }

  static Object? _valeur(Object? valeur) => switch (valeur) {
    final double d when d == d.truncateToDouble() => d.toInt(),
    final bool b => b ? 1 : 0,
    final List<Object?> l => jsonEncode(l),
    final Map<Object?, Object?> m => jsonEncode(m),
    _ => valeur,
  };

  /// Texte stable d'une ligne : mêmes colonnes, même ordre, mêmes nombres.
  static Map<String, Object?> _canonique(Map<String, Object?> ligne, List<String> colonnes) => {
    for (final colonne in colonnes) colonne: _valeur(ligne[colonne]),
  };

  Future<List<String>> _colonnes(DatabaseExecutor db, String table, List<String> ignorer) async {
    final infos = await db.rawQuery('PRAGMA table_info($table)');
    return [
      for (final info in infos)
        if (!ignorer.contains(info['name'])) info['name']! as String,
    ];
  }

  Future<Map<String, String>> _etat(DatabaseExecutor db, String source) async {
    final lignes = await db.query('miroir_etat', where: 'source = ?', whereArgs: [source]);
    return {for (final l in lignes) l['cle']! as String: l['valeur']! as String};
  }

  Future<void> _noterEtat(DatabaseExecutor db, String source, String cle, String? valeur) async {
    if (valeur == null) {
      await db.delete('miroir_etat', where: 'source = ? AND cle = ?', whereArgs: [source, cle]);
    } else {
      await db.insert('miroir_etat', {'source': source, 'cle': cle, 'valeur': valeur}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static String _texteCle(List<Object?> cle) => jsonEncode(cle);

  static String _signature(Map<String, Object?> changement) => jsonEncode(changement);

  Future<List<Map<String, Object?>>> _changementsLocaux(Database db, Set<String> refusees) async {
    final changements = <Map<String, Object?>>[];
    for (final table in tablesMiroir) {
      final colonnes = await _colonnes(db, table.nom, table.ignorer);
      final etat = await _etat(db, table.nom);
      final presentes = <String>{};
      for (final brute in await db.query(table.nom)) {
        final ligne = _canonique(brute, colonnes);
        final cle = [for (final c in table.cle) ligne[c]];
        final texteCle = _texteCle(cle);
        presentes.add(texteCle);
        if (etat[texteCle] != jsonEncode(ligne)) {
          changements.add({'table': table.nom, 'cle': cle, 'ligne': ligne});
        }
      }
      for (final texteCle in etat.keys.where((k) => !presentes.contains(k))) {
        changements.add({'table': table.nom, 'cle': jsonDecode(texteCle), 'ligne': null});
      }
    }
    return changements.where((c) => !refusees.contains(_signature(c))).toList();
  }

  Future<int> _synchroniser(String userId) async {
    final db = await _databaseHelper.database;
    final cleRevision = '${ApiClient.prefixeCache(userId)}miroir_revision';
    final stockee = await db.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: [cleRevision], limit: 1);
    var depuis = stockee.isEmpty ? 0 : int.tryParse(stockee.first['value']! as String) ?? 0;

    final refusees = _refusees.putIfAbsent(userId, () => {});
    final changements = await _changementsLocaux(db, refusees);
    final lignes = <Map<String, Object?>>[];
    Map<String, Object?> serveur = const {};
    var debut = 0;
    do {
      final lot = changements.skip(debut).take(tailleLot).toList();
      final reponse = Map<String, Object?>.from(await _client.post('/miroir/synchroniser', {'depuis': depuis, 'changements': lot}) as Map);
      final refus = {for (final i in reponse['refuses']! as List) (i as num).toInt()};
      for (final (index, changement) in lot.indexed) {
        if (refus.contains(index)) {
          refusees.add(_signature(changement));
          continue;
        }
        final ligne = changement['ligne'];
        await _noterEtat(
          db,
          changement['table']! as String,
          _texteCle(changement['cle']! as List<Object?>),
          ligne == null ? null : jsonEncode(ligne),
        );
      }
      lignes.addAll([for (final l in reponse['lignes']! as List) Map<String, Object?>.from(l as Map)]);
      serveur = Map<String, Object?>.from(reponse['serveur']! as Map);
      depuis = (reponse['revision']! as num).toInt();
      debut += tailleLot;
    } while (debut < changements.length);

    // Sans cela, une ligne enfant reçue avant son compte parent serait rejetée.
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      final modifiees = await db.transaction((txn) async {
        final total = await _appliquerLignes(txn, lignes) + await _appliquerServeur(txn, serveur);
        await txn.insert('app_settings', {'key': cleRevision, 'value': '$depuis'}, conflictAlgorithm: ConflictAlgorithm.replace);
        return total;
      });
      return modifiees;
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<void> _ecrire(Transaction txn, String table, List<String> cle, Map<String, Object?> ligne) async {
    await txn.delete(table, where: cle.map((c) => '$c = ?').join(' AND '), whereArgs: [for (final c in cle) ligne[c]]);
    // Une colonne absente prend sa valeur par défaut au lieu d'être forcée à null.
    await txn.insert(table, {...ligne}..removeWhere((_, valeur) => valeur == null), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> _appliquerLignes(Transaction txn, List<Map<String, Object?>> lignes) async {
    var total = 0;
    for (final recue in lignes) {
      final table = tablesMiroir.where((t) => t.nom == recue['table']).firstOrNull;
      if (table == null) continue;
      final cle = recue['cle']! as List<Object?>;
      final texteCle = _texteCle(cle);
      final where = table.cle.map((c) => '$c = ?').join(' AND ');
      final colonnes = await _colonnes(txn, table.nom, table.ignorer);
      final actuelles = await txn.query(table.nom, where: where, whereArgs: cle, limit: 1);
      final actuelle = actuelles.isEmpty ? null : jsonEncode(_canonique(actuelles.first, colonnes));
      // Modifiée ici depuis le dernier échange : elle partira au prochain envoi.
      final connue = (await txn.query('miroir_etat', columns: ['valeur'], where: 'source = ? AND cle = ?', whereArgs: [table.nom, texteCle], limit: 1)).firstOrNull?['valeur'];
      if (actuelle != connue) continue;
      final brute = recue['ligne'];
      if (brute == null) {
        if (actuelle != null) {
          await txn.delete(table.nom, where: where, whereArgs: cle);
          total++;
        }
        await _noterEtat(txn, table.nom, texteCle, null);
        continue;
      }
      final ligne = _canonique(Map<String, Object?>.from(brute as Map), colonnes);
      if (jsonEncode(ligne) == actuelle) continue;
      try {
        await _ecrire(txn, table.nom, table.cle, ligne);
        // Relue après écriture, pour tenir compte des valeurs par défaut.
        final relue = await txn.query(table.nom, where: where, whereArgs: cle, limit: 1);
        await _noterEtat(txn, table.nom, texteCle, jsonEncode(_canonique(relue.first, colonnes)));
        total++;
      } on DatabaseException {
        // Ligne incompatible avec le schéma local : elle ne bloque pas les autres.
      }
    }
    return total;
  }

  Future<int> _appliquerServeur(Transaction txn, Map<String, Object?> serveur) async {
    var total = 0;
    for (final MapEntry(key: table, value: cle) in tablesServeur.entries) {
      final recues = serveur[table];
      if (recues is! List) continue;
      final source = 'serveur:$table';
      final colonnes = await _colonnes(txn, table, const []);
      final etat = await _etat(txn, source);
      final presentes = <String>{};
      for (final brute in recues) {
        final ligne = _canonique(Map<String, Object?>.from(brute as Map), colonnes);
        final texteCle = _texteCle([for (final c in cle) ligne[c]]);
        presentes.add(texteCle);
        final texte = jsonEncode(ligne);
        if (etat[texteCle] == texte) continue;
        try {
          await _ecrire(txn, table, cle, ligne);
          await _noterEtat(txn, source, texteCle, texte);
          total++;
        } on DatabaseException {
          // Ligne incompatible avec le schéma local : elle ne bloque pas les autres.
        }
      }
      // Seules les lignes venues du serveur sont retirées, jamais d'anciennes lignes locales.
      for (final texteCle in etat.keys.where((k) => !presentes.contains(k))) {
        final valeurs = jsonDecode(texteCle) as List<Object?>;
        await txn.delete(table, where: cle.map((c) => '$c = ?').join(' AND '), whereArgs: valeurs);
        await _noterEtat(txn, source, texteCle, null);
        total++;
      }
    }
    return total;
  }
}
