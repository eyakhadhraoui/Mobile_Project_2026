import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/covoiturage_trajet.dart';
import '../../models/enums_covoiturage.dart';
import '../../providers/auth_provider.dart';
import '../../providers/covoiturage_provider.dart';
import '../../providers/notification_covoiturage_provider.dart';
import 'notifications_covoiturage_screen.dart';
import 'carte_trajets_screen.dart';
import 'covoiturage_widgets.dart';
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
      if (mounted) {
        await context.read<NotificationCovoiturageProvider>().charger(
          p.compte?.id,
        );
      }
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
                icon: Badge(
                  isLabelVisible: p.correspondancesNonVues > 0,
                  label: Text('${p.correspondancesNonVues}'),
                  child: const Icon(Icons.bookmark_outline),
                ),
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
                          CircleAvatar(
                            radius: 21,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            child: const Icon(Icons.place_outlined),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.nom,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                Text(
                                  'Votre zone : ${c.zone}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
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
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_car_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 10),
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
    }
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
  Widget build(BuildContext context) {
    final primaire = Theme.of(context).colorScheme.primary;
    final offre = trajet.type == TypeTrajetEnum.offre;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                  PastilleTrajet(
                    icone: offre ? Icons.directions_car : Icons.person_search,
                    texte: trajet.type.libelle,
                    couleur: primaire,
                  ),
                  const Spacer(),
                  PastilleTrajet(
                    texte: trajet.statut.libelle,
                    couleur: couleurStatutTrajet(trajet.statut),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ItineraireTrajet(depart: trajet.depart, arrivee: trajet.arrivee),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  PastilleTrajet(
                    icone: Icons.event,
                    texte: dateTrajet(trajet.date),
                  ),
                  PastilleTrajet(icone: Icons.schedule, texte: trajet.heure),
                  PastilleTrajet(
                    icone: Icons.event_seat_outlined,
                    texte: '${trajet.places} place(s)',
                  ),
                  if (dansZone)
                    PastilleTrajet(
                      icone: Icons.near_me,
                      texte: 'Dans votre zone',
                      couleur: primaire,
                    ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${trajet.auteurNom} · Nouveau',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (trajet.prix != null)
                    Text(
                      '${trajet.prix!.toStringAsFixed(1)} TND',
                      style: TextStyle(
                        color: primaire,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
