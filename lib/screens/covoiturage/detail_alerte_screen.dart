import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/alerte_trajet.dart';
import '../../providers/alerte_trajet_provider.dart';
import '../../providers/covoiturage_provider.dart';
import 'trajet_detail_screen.dart';

class DetailAlerteScreen extends StatelessWidget {
  const DetailAlerteScreen({super.key, required this.alerte});

  final AlerteTrajet alerte;

  @override
  Widget build(BuildContext context) {
    final alertes = context.watch<AlerteTrajetProvider>();
    final covoiturage = context.watch<CovoiturageProvider>();
    final resultats = alertes.correspondances(alerte, covoiturage.trajets);

    return Scaffold(
      appBar: AppBar(title: const Text('Détail de l’alerte')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${alerte.depart} → ${alerte.arrivee}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${alerte.zone} · ${alerte.typeCible.name} · '
                    '${alerte.creneau.name}',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Alerte active'),
                    value: alerte.active,
                    onChanged: (value) => alertes.actif(alerte, value),
                  ),
                ],
              ),
            ),
          ),
          if (resultats.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucune annonce ne correspond pour le moment. Vous serez '
                'notifié dès qu’une annonce correspondante sera publiée.',
              ),
            ),
          for (final trajet in resultats)
            Card(
              child: ListTile(
                title: Text('${trajet.depart} → ${trajet.arrivee}'),
                subtitle: Text(
                  '${trajet.date} · ${trajet.heure} · Places suffisantes',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrajetDetailScreen(trajetId: trajet.id),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => _supprimer(context, alertes),
            child: const Text('Supprimer cette alerte'),
          ),
        ],
      ),
    );
  }

  Future<void> _supprimer(
    BuildContext context,
    AlerteTrajetProvider provider,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer cette alerte ?'),
        content: const Text('Vous ne serez plus notifié pour ce trajet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await provider.supprimer(alerte);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
