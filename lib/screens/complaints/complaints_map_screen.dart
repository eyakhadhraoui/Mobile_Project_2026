import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/constants/api_constants.dart';
import '../../models/complaint_model.dart';
import '../../providers/complaint_provider.dart';
import '../../services/geocodage_service.dart';
import 'complaint_detail_screen.dart';
import 'complaints_screen.dart';

const _tunis = LatLng(36.8065, 10.1815);

/// Bâtiment sur la carte : une position et les réclamations qui s'y rapportent.
class _Batiment {
  _Batiment(this.position);
  final Coordonnees position;
  final List<ComplaintModel> reclamations = [];

  ComplaintPriority get priorite =>
      reclamations.map((r) => r.priority).reduce((a, b) => a.index >= b.index ? a : b);
}

/// Carte des réclamations pour le propriétaire : les adresses de logement sont
/// géocodées (Nominatim, avec cache SQLite) et regroupées par bâtiment.
class ComplaintsMapScreen extends StatefulWidget {
  const ComplaintsMapScreen({super.key, this.geocodage});

  /// Injection pour les tests.
  final GeocodageService? geocodage;

  @override
  State<ComplaintsMapScreen> createState() => _ComplaintsMapScreenState();
}

class _ComplaintsMapScreenState extends State<ComplaintsMapScreen> {
  late final GeocodageService _service = widget.geocodage ?? GeocodageService();
  late Future<({Map<String, Coordonnees?> positions, bool incomplet})> _localisation;
  bool _ouvertesSeules = true;
  int _faites = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _localisation = _localiser();
  }

  @override
  void dispose() {
    if (widget.geocodage == null) _service.fermer();
    super.dispose();
  }

  static List<ComplaintModel> _actives(List<ComplaintModel> toutes) =>
      toutes.where((r) => !r.isDraft && !r.isDeleted).toList();

  /// Géocode les adresses (une requête par seconde pour les adresses absentes du cache).
  Future<({Map<String, Coordonnees?> positions, bool incomplet})> _localiser() =>
      _service.geocoderTout(
        _actives(context.read<ComplaintProvider>().complaints).map((r) => r.locationId),
        progression: (faites, total) {
          if (mounted) {
            setState(() {
              _faites = faites;
              _total = total;
            });
          }
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Carte des réclamations'),
      actions: [
        FilterChip(
          label: const Text('Non résolues'),
          selected: _ouvertesSeules,
          onSelected: (valeur) => setState(() => _ouvertesSeules = valeur),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: FutureBuilder(
      future: _localisation,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text(_total == 0 ? 'Localisation des adresses…' : 'Localisation des adresses… $_faites/$_total'),
                const SizedBox(height: 4),
                const Text('Une adresse par seconde (règle d’OpenStreetMap).', style: TextStyle(fontSize: 11, color: Color(0xFF647995))),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Impossible de préparer la carte.'));
        }
        return _carte(snapshot.data!.positions, incomplet: snapshot.data!.incomplet);
      },
    ),
  );

  Widget _carte(Map<String, Coordonnees?> positions, {required bool incomplet}) {
    final batiments = <String, _Batiment>{};
    final nonLocalisees = <ComplaintModel>[];
    for (final reclamation in _actives(context.watch<ComplaintProvider>().complaints)) {
      if (_ouvertesSeules && reclamation.status == ComplaintStatus.cloturee) continue;
      final position = positions[GeocodageService.cle(reclamation.locationId)];
      if (position == null) {
        nonLocalisees.add(reclamation);
        continue;
      }
      // Même point (à ~1 m près) = même bâtiment.
      final cle = '${position.lat.toStringAsFixed(5)},${position.lon.toStringAsFixed(5)}';
      batiments.putIfAbsent(cle, () => _Batiment(position)).reclamations.add(reclamation);
    }
    final points = [for (final b in batiments.values) LatLng(b.position.lat, b.position.lon)];
    final incidents = context.watch<ComplaintProvider>().incidents;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: points.isEmpty ? _tunis : points.first,
            initialZoom: points.isEmpty ? 11 : 15,
            initialCameraFit: points.length < 2
                ? null
                : CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(56), maxZoom: 16),
          ),
          children: [
            TileLayer(urlTemplate: ApiConstants.tuilesOsm, userAgentPackageName: 'com.example.studenthub'),
            MarkerLayer(
              markers: [
                for (final batiment in batiments.values)
                  Marker(
                    point: LatLng(batiment.position.lat, batiment.position.lon),
                    width: 40 + (batiment.reclamations.length.clamp(1, 10) * 3),
                    height: 40 + (batiment.reclamations.length.clamp(1, 10) * 3),
                    child: _Pastille(
                      batiment: batiment,
                      incident: batiment.reclamations.any((r) => incidents.any((i) => i.contient(r.id))),
                      onTap: () => _ouvrirBatiment(batiment),
                    ),
                  ),
              ],
            ),
            const SimpleAttributionWidget(source: Text('Contributeurs OpenStreetMap')),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 10,
          child: Column(
            children: [
              if (incomplet)
                const _Info(
                  icone: Icons.cloud_off,
                  texte: 'Hors ligne : seules les adresses déjà localisées sont affichées.',
                ),
              if (nonLocalisees.isNotEmpty)
                _Info(
                  icone: Icons.location_off_outlined,
                  texte: '${nonLocalisees.length} réclamation(s) sans adresse reconnue',
                  action: () => _afficherListe('Adresses non localisées', nonLocalisees),
                ),
              if (batiments.isEmpty && nonLocalisees.isEmpty)
                const _Info(icone: Icons.check_circle_outline, texte: 'Aucune réclamation à afficher.'),
            ],
          ),
        ),
      ],
    );
  }

  void _ouvrirBatiment(_Batiment batiment) => _afficherListe(
    batiment.position.libelle.isEmpty ? batiment.reclamations.first.locationId : batiment.position.libelle,
    batiment.reclamations,
  );

  void _afficherListe(String titre, List<ComplaintModel> reclamations) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .6),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          children: [
            Text(titre, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${reclamations.length} réclamation(s)', style: const TextStyle(fontSize: 12, color: Color(0xFF647995))),
            const SizedBox(height: 8),
            for (final reclamation in reclamations)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(complaintCategoryIcon(reclamation.category), color: _couleur(reclamation.priority)),
                title: Text(reclamation.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${complaintStatusLabel(reclamation.status)} · ${reclamation.locationId}', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ComplaintDetailScreen(complaint: reclamation, canManageStatus: true, canEdit: false),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
}

Color _couleur(ComplaintPriority priorite) => switch (priorite) {
  ComplaintPriority.urgente => const Color(0xFFD75B4B),
  ComplaintPriority.moyenne => const Color(0xFFDD9132),
  ComplaintPriority.faible => const Color(0xFF53A977),
};

/// Pastille d'un bâtiment : couleur selon la priorité la plus haute, nombre de
/// réclamations, contour noir si un incident collectif y est en cours.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.batiment, required this.incident, required this.onTap});
  final _Batiment batiment;
  final bool incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Tooltip(
      message: '${batiment.reclamations.length} réclamation(s)${incident ? ' · incident collectif' : ''}',
      child: Container(
        decoration: BoxDecoration(
          color: _couleur(batiment.priorite),
          shape: BoxShape.circle,
          border: Border.all(color: incident ? const Color(0xFF172B45) : Colors.white, width: incident ? 3 : 2),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: Text(
          '${batiment.reclamations.length}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.icone, required this.texte, this.action});
  final IconData icone;
  final String texte;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      dense: true,
      leading: Icon(icone, size: 20),
      title: Text(texte, style: const TextStyle(fontSize: 12)),
      trailing: action == null ? null : const Icon(Icons.chevron_right),
      onTap: action,
    ),
  );
}
