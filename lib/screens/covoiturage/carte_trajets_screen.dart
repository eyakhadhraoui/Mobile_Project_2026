import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../models/alerte_trajet.dart';
import '../../models/covoiturage_trajet.dart';
import '../../models/enums_covoiturage.dart';
import '../../providers/alerte_trajet_provider.dart';
import '../../providers/covoiturage_provider.dart';
import '../../services/covoiturage_alertes.dart';
import '../../services/covoiturage_geo.dart';
import 'trajet_detail_screen.dart';
import 'trajet_form_screen.dart';

class CarteTrajetsScreen extends StatefulWidget {
  const CarteTrajetsScreen({super.key});

  @override
  State<CarteTrajetsScreen> createState() => _CarteTrajetsScreenState();
}

class _CarteTrajetsScreenState extends State<CarteTrajetsScreen> {
  bool _afficherAlertes = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AlerteTrajetProvider>().charger(
        context.read<CovoiturageProvider>().compte?.id,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Consumer<CovoiturageProvider>(
    builder: (context, provider, _) {
      final alertes = context
          .watch<AlerteTrajetProvider>()
          .alertes
          .where((a) => a.active && a.zone == provider.compte?.zone)
          .toList();
      final compte = provider.compte;
      if (compte == null || provider.chargement)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final trajets = provider.trajetsCarte;
      final centre = trajets.isEmpty
          ? CovoiturageGeo.centreZone(compte.zone)
          : CovoiturageGeo.positionDepart(trajets.first);
      final selection = provider.trajetCarteSelectionne;
      return Scaffold(
        appBar: AppBar(title: const Text('Carte des trajets')),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'carte_covoiturage_fab',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TrajetFormScreen()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Publier un trajet'),
        ),
        body: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: centre,
                initialZoom: 12,
                onTap: (_, _) => provider.selectionnerTrajetCarte(null),
              ),
              children: [
                TileLayer(
                  urlTemplate: CovoiturageGeo.tuilesOpenStreetMap,
                  userAgentPackageName: 'com.example.studenthub',
                ),
                PolylineLayer(
                  polylines: [
                    if (selection != null)
                      Polyline(
                        points: [
                          CovoiturageGeo.positionDepart(selection),
                          CovoiturageGeo.positionArrivee(selection),
                        ],
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 3,
                      ),
                    if (_afficherAlertes)
                      for (final alerte in alertes)
                        Polyline(
                          points: [
                            CovoiturageAlertes.positionDepartAlerte(alerte),
                            CovoiturageAlertes.positionArriveeAlerte(alerte),
                          ],
                          color: Colors.teal.withValues(alpha: .75),
                          strokeWidth: 3,
                        ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final trajet in trajets) _marker(provider, trajet),
                    if (_afficherAlertes)
                      for (final alerte in alertes) _alerteMarker(alerte),
                  ],
                ),
                RichAttributionWidget(
                  attributions: const [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text('Zone : ${compte.zone}')),
                  _filtre(provider, null, 'Tous'),
                  _filtre(provider, TypeTrajetEnum.offre, 'Offres'),
                  _filtre(provider, TypeTrajetEnum.demande, 'Demandes'),
                  FilterChip(
                    label: const Text('Mes alertes'),
                    avatar: const Icon(Icons.notifications_active_outlined),
                    selected: _afficherAlertes,
                    onSelected: (value) =>
                        setState(() => _afficherAlertes = value),
                  ),
                ],
              ),
            ),
            if (trajets.isEmpty) _vide(context),
            if (selection != null) _fiche(context, selection),
          ],
        ),
      );
    },
  );
  ChoiceChip _filtre(
    CovoiturageProvider p,
    TypeTrajetEnum? valeur,
    String texte,
  ) => ChoiceChip(
    label: Text(texte),
    selected: p.filtreCarte == valeur,
    onSelected: (_) => p.definirFiltreCarte(valeur),
  );
  Marker _marker(CovoiturageProvider p, CovoiturageTrajet t) {
    final selection = p.trajetCarteSelectionne;
    final actif = selection == null || selection.id == t.id;
    final couleur = t.estOffre ? Colors.blue : Colors.orange;
    return Marker(
      point: CovoiturageGeo.positionDepart(t),
      width: 80,
      height: 80,
      child: Opacity(
        opacity: actif ? 1 : .35,
        child: GestureDetector(
          onTap: () => p.selectionnerTrajetCarte(t),
          child: Column(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white,
                radius: selection?.id == t.id ? 25 : 22,
                child: CircleAvatar(
                  backgroundColor: couleur,
                  radius: selection?.id == t.id ? 21 : 18,
                  child: Text(
                    t.auteurNom
                        .split(' ')
                        .map((v) => v.isEmpty ? '' : v[0])
                        .take(2)
                        .join(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              Text(
                t.prix == null
                    ? 'Demande'
                    : '${t.prix!.toStringAsFixed(0)} TND',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Marker _alerteMarker(AlerteTrajet alerte) => Marker(
    point: CovoiturageAlertes.positionDepartAlerte(alerte),
    width: 72,
    height: 72,
    child: Tooltip(
      message: 'Alerte : ${alerte.depart} → ${alerte.arrivee}',
      child: const Icon(
        Icons.notifications_active,
        color: Colors.teal,
        size: 38,
      ),
    ),
  );

  Widget _vide(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Aucun trajet dans votre zone pour le moment'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrajetFormScreen()),
              ),
              child: const Text('Publier un trajet'),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _fiche(BuildContext context, CovoiturageTrajet t) =>
      DraggableScrollableSheet(
        initialChildSize: .35,
        minChildSize: .25,
        maxChildSize: .75,
        builder: (_, controller) => Material(
          color: Colors.white,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${t.depart} → ${t.arrivee}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('${t.date} · ${t.heure} · ${t.places} place(s)'),
              if (t.prix != null) Text('Participation : ${t.prix} TND'),
              if (t.commentaire.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t.commentaire),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrajetDetailScreen(trajetId: t.id),
                  ),
                ),
                child: const Text('Voir les détails'),
              ),
            ],
          ),
        ),
      );
}
