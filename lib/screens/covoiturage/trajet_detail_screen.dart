import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/covoiturage_trajet.dart';
import '../../models/enums_covoiturage.dart';
import '../../models/reservation_trajet.dart';
import '../../providers/covoiturage_provider.dart';
import 'covoiturage_widgets.dart';
import 'trajet_form_screen.dart';

class _LigneInfo extends StatelessWidget {
  const _LigneInfo(this.icone, this.texte);
  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(texte, style: const TextStyle(height: 1.3))),
      ],
    ),
  );
}

class TrajetDetailScreen extends StatefulWidget {
  const TrajetDetailScreen({
    super.key,
    required this.trajetId,
  });

  final String trajetId;

  @override
  State<TrajetDetailScreen> createState() => _TrajetDetailScreenState();
}

class _TrajetDetailScreenState extends State<TrajetDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final p = context.watch<CovoiturageProvider>();
    final matches = p.trajets.where((x) => x.id == widget.trajetId);
    final CovoiturageTrajet? t = matches.isEmpty ? null : matches.first;

    if (t == null) {
      return const Scaffold(
        body: Center(
          child: Text('Trajet introuvable'),
        ),
      );
    }

    final mine = t.auteurId == p.compte!.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Détail du trajet')),
      body: FutureBuilder<List<ReservationTrajet>>(
        future: p.reservations(t.id),
        builder: (context, s) {
          final rs = s.data ?? [];
          final confirmed = rs
              .where((r) => r.statut == StatutReservationEnum.confirmee)
              .fold(0, (n, r) => n + r.placesReservees);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          PastilleTrajet(
                            texte: t.type.libelle,
                            couleur: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          PastilleTrajet(
                            texte: t.statut.libelle,
                            couleur: couleurStatutTrajet(t.statut),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ItineraireTrajet(
                        depart: t.depart,
                        arrivee: t.arrivee,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Divider(height: 32),
                      _LigneInfo(
                        Icons.event,
                        '${dateTrajet(t.date)} à ${t.heure}',
                      ),
                      _LigneInfo(Icons.place_outlined, t.zone),
                      _LigneInfo(
                        Icons.person_outline,
                        'Conducteur / auteur : ${t.auteurNom} · Nouveau',
                      ),
                      _LigneInfo(
                        Icons.event_seat_outlined,
                        'Places restantes : ${t.places - confirmed}/${t.places}',
                      ),
                      if (t.prix != null)
                        _LigneInfo(
                          Icons.payments_outlined,
                          'Participation : ${t.prix} TND',
                        ),
                      if (t.commentaire.isNotEmpty)
                        _LigneInfo(Icons.notes, t.commentaire),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (mine && t.statut != StatutTrajetEnum.annule) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TrajetFormScreen(trajet: t),
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Modifier'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _annulerTrajet(t),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Annuler'),
                      ),
                    ),
                  ],
                ),
              ] else if (t.statut == StatutTrajetEnum.ouvert) ...[
                FilledButton(
                  onPressed: () => _reserver(t),
                  child: Text(
                    t.type == TypeTrajetEnum.offre ? 'Réserver' : 'Je peux l’emmener',
                  ),
                ),
              ],
              if (mine && rs.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 18),
                  child: Text(
                    'Réservations / propositions',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final r in rs)
                  Card(
                    child: ListTile(
                      title: Text(r.participantNom),
                      subtitle: Text('${r.placesReservees} place(s) · ${r.statut.libelle}'),
                      trailing: r.statut == StatutReservationEnum.enAttente
                          ? Wrap(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check, color: Colors.green),
                                  onPressed: () => p.repondre(t, r, true),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.red),
                                  onPressed: () => p.repondre(t, r, false),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
              ],
              if (!mine) ...[
                for (final r in rs.where(
                  (r) =>
                      r.participantId == p.compte!.id &&
                      [
                        StatutReservationEnum.enAttente,
                        StatutReservationEnum.confirmee,
                      ].contains(r.statut),
                ))
                  OutlinedButton(
                    onPressed: () => p.annulerReservation(t, r),
                    child: const Text('Annuler ma réservation'),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _reserver(CovoiturageTrajet t) async {
    var places = 1;

    if (t.type == TypeTrajetEnum.offre) {
      final r = await showDialog<int>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Nombre de places'),
          content: DropdownButtonFormField<int>(
            initialValue: 1,
            items: List.generate(
              t.places,
              (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
            ).toList(),
            onChanged: (v) => places = v!,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, places),
              child: const Text('Réserver'),
            ),
          ],
        ),
      );
      if (r == null) return;
      places = r;
    }

    if (!mounted) return;
    try {
      await context.read<CovoiturageProvider>().demander(t, places);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demande envoyée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _annulerTrajet(CovoiturageTrajet t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Annuler ce trajet ?'),
        content: const Text('Les réservations associées seront annulées.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler le trajet'),
          ),
        ],
      ),
    );

    if (yes == true && mounted) {
      await context.read<CovoiturageProvider>().annulerTrajet(t);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trajet annulé')),
        );
        Navigator.pop(context);
      }
    }
  }
}

