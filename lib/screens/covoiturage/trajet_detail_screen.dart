import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/covoiturage_trajet.dart';
import '../../models/enums_covoiturage.dart';
import '../../models/reservation_trajet.dart';
import '../../providers/covoiturage_provider.dart';
import 'trajet_form_screen.dart';

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
                      Text(
                        '${t.depart} → ${t.arrivee}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text('${t.date} à ${t.heure} · ${t.zone}'),
                      Text('${t.type.libelle} · ${t.statut.libelle}'),
                      Text('Conducteur / auteur : ${t.auteurNom} · Nouveau'),
                      Text('Places restantes : ${t.places - confirmed}/${t.places}'),
                      if (t.prix != null) Text('Participation : ${t.prix} TND'),
                      if (t.commentaire.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(t.commentaire),
                      ],
                    ],
                  ),
                ),
              ),
              if (mine && t.statut != StatutTrajetEnum.annule) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TrajetFormScreen(trajet: t),
                          ),
                        ),
                        child: const Text('Modifier'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => _annulerTrajet(t),
                        child: const Text('Annuler'),
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
            value: 1,
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

    if (yes == true) {
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

