import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/housing_service.dart';
import 'housing_actions.dart';

/// Visites et demandes de location reçues (propriétaire) et envoyées (étudiant),
/// plus la gestion des créneaux de visite du propriétaire.
class HousingRequestsScreen extends StatefulWidget {
  const HousingRequestsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<HousingRequestsScreen> createState() => _HousingRequestsScreenState();
}

class _HousingRequestsScreenState extends State<HousingRequestsScreen> {
  final _service = HousingService();
  late Future<_Donnees> _donnees = _charger();

  Future<_Donnees> _charger() async {
    final results = await Future.wait([_service.visites(), _service.demandesLocation(), _service.disponibilites()]);
    final visites = results[0] as ({List<DemandeLogement> recues, List<DemandeLogement> envoyees});
    final demandes = results[1] as ({List<DemandeLogement> recues, List<DemandeLogement> envoyees});
    return _Donnees(visites, demandes, results[2] as List<Map<String, dynamic>>);
  }

  Future<void> _recharger() async {
    final future = _charger();
    setState(() => _donnees = future);
    await future.catchError((_) => _Donnees.vide());
  }

  Future<void> _action(Future<void> Function() action, String succes) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(succes)));
      await _recharger();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: widget.initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Visites et demandes'),
        actions: [IconButton(onPressed: _recharger, icon: const Icon(Icons.refresh), tooltip: 'Actualiser')],
        bottom: const TabBar(tabs: [Tab(text: 'Reçues'), Tab(text: 'Envoyées'), Tab(text: 'Mes créneaux')]),
      ),
      body: FutureBuilder<_Donnees>(
        future: _donnees,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) {
            return _Vide(
              icon: Icons.cloud_off,
              texte: snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'Chargement impossible.',
              action: TextButton(onPressed: _recharger, child: const Text('Réessayer')),
            );
          }
          final d = snapshot.data!;
          return TabBarView(
            children: [
              _liste([
                ...d.demandes.recues.map((r) => _demandeCard(r, proprietaire: true)),
                ...d.visites.recues.map((v) => _visiteCard(v, proprietaire: true)),
              ], 'Aucune visite ni demande reçue.'),
              _liste([
                ...d.demandes.envoyees.map((r) => _demandeCard(r, proprietaire: false)),
                ...d.visites.envoyees.map((v) => _visiteCard(v, proprietaire: false)),
              ], 'Vous n’avez encore rien demandé.'),
              _creneaux(d.disponibilites),
            ],
          );
        },
      ),
    ),
  );

  Widget _liste(List<Widget> items, String vide) => RefreshIndicator(
    onRefresh: _recharger,
    child: items.isEmpty
        ? ListView(children: [const SizedBox(height: 120), _Vide(icon: Icons.inbox_outlined, texte: vide)])
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => items[i],
          ),
  );

  Widget _demandeCard(DemandeLogement r, {required bool proprietaire}) {
    final debut = r.date('startDate'), fin = r.date('endDate');
    final pending = r.statut == 'pending';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.key, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Demande de location · ${r.annonceTitre}', style: const TextStyle(fontWeight: FontWeight.w700))),
              _StatutChip(r.statut),
            ]),
            const SizedBox(height: 6),
            Text(proprietaire ? 'De : ${r.clientNom}' : 'Propriétaire : ${r.proprietaireNom}'),
            Text('Loyer : ${formatMontant((r.data['monthlyRent'] as num? ?? 0).toDouble())} / mois'),
            if (debut != null && fin != null) Text('Du ${formatJour(debut)} au ${formatJour(fin)} (${r.data['duration']} mois)'),
            Text('Paiement : ${_frequence(r.data['paymentFrequency'])} · ${_moyen(r.data['paymentMethod'])}'),
            if ((r.data['additionalMessage'] as String? ?? '').isNotEmpty) Text('« ${r.data['additionalMessage']} »'),
            if (pending)
              Wrap(spacing: 8, children: [
                if (proprietaire) ...[
                  FilledButton.icon(
                    onPressed: () => _action(() => _service.repondreDemande(r.id, 'accepted'), 'Demande acceptée.'),
                    icon: const Icon(Icons.check),
                    label: const Text('Accepter'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _action(() => _service.repondreDemande(r.id, 'refused'), 'Demande refusée.'),
                    icon: const Icon(Icons.close),
                    label: const Text('Refuser'),
                  ),
                ] else
                  OutlinedButton(
                    onPressed: () => _action(() => _service.repondreDemande(r.id, 'cancelled'), 'Demande annulée.'),
                    child: const Text('Annuler ma demande'),
                  ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _visiteCard(DemandeLogement v, {required bool proprietaire}) {
    final debut = v.date('startAt'), fin = v.date('endAt');
    final aVenir = v.statut == 'confirmed' && fin != null && fin.isAfter(DateTime.now());
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_available),
        title: Text('Visite · ${v.annonceTitre}'),
        subtitle: Text([
          if (debut != null && fin != null) '${formatJour(debut)} · ${formatHeure(debut)} – ${formatHeure(fin)}',
          proprietaire ? 'Visiteur : ${v.clientNom}' : 'Propriétaire : ${v.proprietaireNom}',
        ].join('\n')),
        isThreeLine: true,
        trailing: aVenir
            ? TextButton(
                onPressed: () => _action(() => _service.annulerVisite(v.id), 'Visite annulée.'),
                child: const Text('Annuler'),
              )
            : _StatutChip(v.statut == 'confirmed' ? 'done' : v.statut),
      ),
    );
  }

  Widget _creneaux(List<Map<String, dynamic>> disponibilites) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('Vos plages de visite s’appliquent à tous vos logements publiés. Les créneaux réservés sont bloqués automatiquement.'),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () async {
          if (await HousingActions.addAvailability(context, service: _service)) await _recharger();
        },
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une disponibilité'),
      ),
      const SizedBox(height: 12),
      if (disponibilites.isEmpty) const _Vide(icon: Icons.event_busy, texte: 'Aucune disponibilité enregistrée.'),
      ...disponibilites.map((a) {
        final debut = DateTime.tryParse(a['startDate'] as String? ?? ''), fin = DateTime.tryParse(a['endDate'] as String? ?? '');
        return Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_month),
            title: Text(debut == null || fin == null ? '' : 'Du ${formatJour(debut)} au ${formatJour(fin)}'),
            subtitle: Text('${a['startTime']} – ${a['endTime']} · visites de ${a['durationMinutes']} min, pause ${a['breakMinutes']} min'),
            trailing: IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _action(() => _service.supprimerDisponibilite(a['id'] as String), 'Disponibilité supprimée.'),
            ),
          ),
        );
      }),
    ],
  );

  static String _frequence(Object? v) => switch (v) {
    'MONTHLY' => 'mensuel', 'QUARTERLY' => 'trimestriel', 'SEMI_ANNUALLY' => 'semestriel', 'ANNUALLY' => 'annuel', _ => '-',
  };
  static String _moyen(Object? v) => switch (v) {
    'BANK_TRANSFER' => 'virement', 'CHEQUE' => 'chèque', 'CASH' => 'espèces', _ => 'autre',
  };
}

class _Donnees {
  _Donnees(this.visites, this.demandes, this.disponibilites);
  _Donnees.vide()
    : visites = (recues: const [], envoyees: const []),
      demandes = (recues: const [], envoyees: const []),
      disponibilites = const [];
  final ({List<DemandeLogement> recues, List<DemandeLogement> envoyees}) visites;
  final ({List<DemandeLogement> recues, List<DemandeLogement> envoyees}) demandes;
  final List<Map<String, dynamic>> disponibilites;
}

class _StatutChip extends StatelessWidget {
  const _StatutChip(this.statut);
  final String statut;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (statut) {
      'pending' => ('En attente', const Color(0xFFB7791F)),
      'accepted' => ('Acceptée', const Color(0xFF16804A)),
      'refused' => ('Refusée', const Color(0xFFC53030)),
      'cancelled' => ('Annulée', const Color(0xFF647995)),
      'confirmed' => ('Confirmée', const Color(0xFF16804A)),
      'done' => ('Passée', const Color(0xFF647995)),
      _ => (statut, const Color(0xFF647995)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide({required this.icon, required this.texte, this.action});
  final IconData icon;
  final String texte;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 40, color: const Color(0xFF91A6BC)),
        const SizedBox(height: 8),
        Text(texte, textAlign: TextAlign.center),
        ?action,
      ]),
    ),
  );
}
