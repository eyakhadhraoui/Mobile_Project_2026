import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/alerte_trajet_provider.dart';
import '../../providers/covoiturage_provider.dart';
import 'formulaire_alerte_screen.dart';
import 'detail_alerte_screen.dart';
import 'trajet_detail_screen.dart';

class MesAlertesScreen extends StatefulWidget {
  const MesAlertesScreen({super.key});
  @override
  State<MesAlertesScreen> createState() => _MesAlertesScreenState();
}

class _MesAlertesScreenState extends State<MesAlertesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final covoiturage = context.read<CovoiturageProvider>();
      context.read<AlerteTrajetProvider>().charger(covoiturage.compte?.id);
      covoiturage.marquerCorrespondancesVues();
    });
  }

  @override
  Widget build(BuildContext context) {
    final alertes = context.watch<AlerteTrajetProvider>();
    final cov = context.watch<CovoiturageProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Mes alertes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: alertes.alertes.length >= 5
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FormulaireAlerteScreen(),
                ),
              ),
        icon: const Icon(Icons.add_alert),
        label: const Text('Créer'),
      ),
      body: alertes.alertes.isEmpty && cov.correspondances.isEmpty
          ? const Center(child: Text('Aucune alerte pour le moment'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (cov.correspondances.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Correspondances avec vos trajets',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  for (final m in cov.correspondances)
                    Card(
                      child: ListTile(
                        leading: Icon(m.autre.estOffre ? Icons.directions_car : Icons.person_search),
                        title: Text('${m.autre.depart} → ${m.autre.arrivee}'),
                        subtitle: Text(
                          '${m.autre.estOffre ? 'Offre' : 'Demande'} de ${m.autre.auteurNom}\n'
                          '${m.autre.date} · ${m.autre.heure} · ${m.autre.places} place(s)',
                        ),
                        isThreeLine: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TrajetDetailScreen(trajetId: m.autre.id),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                for (final alerte in alertes.alertes)
                  Card(
                    child: ListTile(
                      title: Text('${alerte.depart} → ${alerte.arrivee}'),
                      subtitle: Text(
                        '${alerte.zone} · ${alerte.creneau.name} · ${alertes.correspondances(alerte, cov.trajets).length} correspondance(s)',
                      ),
                      trailing: Switch(
                        value: alerte.active,
                        onChanged: (value) => alertes.actif(alerte, value),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailAlerteScreen(alerte: alerte),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
