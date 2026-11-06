import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/housing_service.dart';
import 'housing_actions.dart';

/// Activité sur mes annonces (likes, commentaires, avis, visites, demandes,
/// modération) et réponses à mes demandes de location, en un seul appel serveur.
class AnnouncementNotificationsScreen extends StatefulWidget {
  const AnnouncementNotificationsScreen({super.key});

  @override
  State<AnnouncementNotificationsScreen> createState() => _AnnouncementNotificationsScreenState();
}

class _AnnouncementNotificationsScreenState extends State<AnnouncementNotificationsScreen> {
  final _service = HousingService();
  late Future<List<ActiviteAnnonce>> _activites = _service.activite();

  Future<void> _recharger() async {
    final future = _service.activite();
    setState(() => _activites = future);
    await future.catchError((_) => <ActiviteAnnonce>[]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Activité des annonces'),
      actions: [IconButton(onPressed: _recharger, icon: const Icon(Icons.refresh), tooltip: 'Actualiser')],
    ),
    body: FutureBuilder<List<ActiviteAnnonce>>(
      future: _activites,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'Chargement impossible.';
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message, textAlign: TextAlign.center)));
        }
        final items = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _recharger,
          child: items.isEmpty
              ? ListView(children: const [SizedBox(height: 160), Center(child: Text('Aucune activité pour le moment.'))])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final (icon, color, action) = _presentation(item);
                    final detail = _detail(item);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(icon, color: color)),
                        title: Text('${item.auteur} $action'),
                        subtitle: Text(detail.isEmpty ? item.annonceTitre : '${item.annonceTitre}\n$detail'),
                        isThreeLine: detail.isNotEmpty,
                        trailing: item.date == null ? null : Text(formatJour(item.date!), style: const TextStyle(fontSize: 11)),
                      ),
                    );
                  },
                ),
        );
      },
    ),
  );

  (IconData, Color, String) _presentation(ActiviteAnnonce item) => switch (item.type) {
    'like' => (Icons.favorite, Colors.red, 'a aimé votre annonce'),
    'commentaire' => (Icons.mode_comment_outlined, Colors.blueGrey, 'a commenté votre annonce'),
    'avis' => (Icons.star, Colors.amber, 'a noté votre annonce'),
    'visite' => (Icons.event_available, Colors.teal, 'a réservé une visite'),
    'demande' => (Icons.key, Colors.indigo, 'a demandé la location'),
    'reponse' => (Icons.mark_email_read_outlined, Colors.green, 'a répondu à votre demande'),
    'moderation' => (Icons.gavel, Colors.orange, 'a refusé ou archivé votre annonce'),
    _ => (Icons.notifications, Colors.blueGrey, ''),
  };

  String _detail(ActiviteAnnonce item) => switch (item.type) {
    'commentaire' => '« ${item.detail} »',
    'demande' || 'reponse' => switch (item.detail) {
      'pending' => 'En attente de réponse',
      'accepted' => 'Acceptée',
      'refused' => 'Refusée',
      'cancelled' => 'Annulée',
      _ => item.detail,
    },
    'visite' => item.detail.replaceFirst('T', ' '),
    _ => item.detail,
  };
}
