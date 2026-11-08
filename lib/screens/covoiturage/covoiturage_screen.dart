import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/covoiturage_trajet.dart';
import '../../models/enums_covoiturage.dart';
import '../../providers/auth_provider.dart';
import '../../providers/covoiturage_provider.dart';
import '../../providers/notification_covoiturage_provider.dart';
import 'notifications_covoiturage_screen.dart';
import 'carte_trajets_screen.dart';
import 'mes_alertes_screen.dart';
import 'trajet_detail_screen.dart';
import 'trajet_form_screen.dart';

const villesCovoiturage = [
  'Tunis',
  'Ariana',
  'Ben Arous',
  'La Manouba',
  'Sousse',
  'Sfax',
  'Nabeul',
  'Monastir',
  'Bizerte',
];

class CovoiturageScreen extends StatefulWidget {
  const CovoiturageScreen({super.key});
  @override
  State<CovoiturageScreen> createState() => _CovoiturageScreenState();
}

class _CovoiturageScreenState extends State<CovoiturageScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _search = TextEditingController();
  bool _maZone = false;
  bool _started = false;
  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _init() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final p = context.read<CovoiturageProvider>();
      await p.initialiser(
        sessionUserId: context.read<AuthProvider>().currentUserId,
      );
      if (mounted)
        await context.read<NotificationCovoiturageProvider>().charger(
          p.compte?.id,
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    _init();
    return Consumer<CovoiturageProvider>(
      builder: (context, p, _) {
        final c = p.compte;
        final nonLues = context
            .watch<NotificationCovoiturageProvider>()
            .nonLues;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Covoiturage'),
            actions: [
              IconButton(
                tooltip: 'Mes alertes',
                onPressed: c == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MesAlertesScreen(),
                        ),
                      ),
                icon: const Icon(Icons.bookmark_outline),
              ),
              IconButton(
                tooltip: 'Voir sur la carte',
                onPressed: c == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CarteTrajetsScreen(),
                        ),
                      ),
                icon: const Icon(Icons.map_outlined),
              ),
              IconButton(
                onPressed: c == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const NotificationsCovoiturageScreen(),
                        ),
                      ),
                icon: Badge(
                  isLabelVisible: nonLues > 0,
                  label: Text('$nonLues'),
                  child: const Icon(Icons.notifications_outlined),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'covoiturage_fab',
            onPressed: c == null
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TrajetFormScreen()),
                  ),
            icon: const Icon(Icons.add),
            label: const Text('Publier'),
          ),
          body: c == null || (p.chargement && p.trajets.isEmpty)
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Connecté : ${c.nom}\nVotre zone : ${c.zone}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _choisirZone(p),
                            child: const Text('Changer'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Rechercher départ ou destination',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      dense: true,
                      value: _maZone,
                      onChanged: (v) => setState(() => _maZone = v),
                      title: const Text('Ma zone uniquement'),
                    ),
                    TabBar(
                      controller: _tabs,
                      tabs: const [
                        Tab(text: 'Offres'),
                        Tab(text: 'Demandes'),
                        Tab(text: 'Mes trajets'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _liste(p, TypeTrajetEnum.offre),
                          _liste(p, TypeTrajetEnum.demande),
                          _liste(p, null, mes: true),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _liste(
    CovoiturageProvider p,
    TypeTrajetEnum? type, {
    bool mes = false,
  }) {
    final q = _search.text.trim().toLowerCase();
    final list = p.trajets
        .where(
          (t) =>
              (type == null || t.type == type) &&
              (!mes || t.auteurId == p.compte!.id) &&
              (!_maZone || t.zone == p.compte!.zone) &&
              (q.isEmpty ||
                  t.depart.toLowerCase().contains(q) ||
                  t.arrivee.toLowerCase().contains(q)),
        )
        .toList();
    if (list.isEmpty)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              type == TypeTrajetEnum.demande
                  ? 'Aucune demande pour le moment'
                  : mes
                  ? 'Aucun de vos trajets'
                  : 'Aucune offre pour le moment',
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrajetFormScreen()),
              ),
              child: Text(
                type == TypeTrajetEnum.demande
                    ? 'Publier une demande'
                    : 'Proposer un trajet',
              ),
            ),
          ],
        ),
      );
    return RefreshIndicator(
      onRefresh: p.actualiser,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (_, i) => _TrajetCard(
          trajet: list[i],
          dansZone: list[i].zone == p.compte!.zone,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TrajetDetailScreen(trajetId: list[i].id),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _choisirZone(CovoiturageProvider p) async {
    final z = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Choisir votre zone'),
        children: [
          for (final v in villesCovoiturage)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, v),
              child: Text(v),
            ),
        ],
      ),
    );
    if (z != null) await p.changerZone(z);
  }
}

class _TrajetCard extends StatelessWidget {
  const _TrajetCard({
    required this.trajet,
    required this.dansZone,
    required this.onTap,
  });
  final CovoiturageTrajet trajet;
  final bool dansZone;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(label: Text(trajet.type.libelle)),
                const Spacer(),
                Text(trajet.statut.libelle),
              ],
            ),
            Text(
              '${trajet.depart}  →  ${trajet.arrivee}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${trajet.date} · ${trajet.heure} · ${trajet.places} place(s)${trajet.prix == null ? '' : ' · ${trajet.prix!.toStringAsFixed(1)} TND'}',
            ),
            Text(
              '${trajet.auteurNom} · Nouveau',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (dansZone)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Chip(
                  avatar: Icon(Icons.near_me, size: 16),
                  label: Text('Dans votre zone'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
