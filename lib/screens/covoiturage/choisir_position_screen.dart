import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/covoiturage_geo.dart';

class ChoisirPositionScreen extends StatefulWidget {
  const ChoisirPositionScreen({
    super.key,
    required this.titre,
    required this.zone,
    this.initiale,
    this.choixVille = false,
  });
  final String titre, zone;
  final LatLng? initiale;

  /// Remplace « Centre de la zone » par une liste de villes à rejoindre.
  final bool choixVille;

  @override
  State<ChoisirPositionScreen> createState() => _ChoisirPositionScreenState();
}

class _ChoisirPositionScreenState extends State<ChoisirPositionScreen> {
  late LatLng _position =
      widget.initiale ?? CovoiturageGeo.centreZone(widget.zone);
  final _carte = MapController();

  /// Le repère est fixe au centre : choisir un point revient à y centrer la carte.
  void _centrerSur(LatLng point) => _carte.move(point, _carte.camera.zoom);

  static String _nomVille(String zone) => zone
      .split(' ')
      .map((mot) => '${mot[0].toUpperCase()}${mot.substring(1)}')
      .join(' ');

  @override
  void dispose() {
    _carte.dispose();
    super.dispose();
  }

  Widget _choixVille(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return Material(
      color: couleurs.surface,
      elevation: 3,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<String>(
        tooltip: 'Aller à une ville',
        onSelected: (zone) => _centrerSur(CovoiturageGeo.centreZone(zone)),
        itemBuilder: (_) => [
          for (final zone in CovoiturageGeo.centresZones.keys)
            PopupMenuItem(value: zone, child: Text(_nomVille(zone))),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_city, size: 18, color: couleurs.primary),
              const SizedBox(width: 8),
              const Text('Aller à une ville'),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.titre)),
    body: Stack(
      children: [
        FlutterMap(
          mapController: _carte,
          options: MapOptions(
            initialCenter: _position,
            initialZoom: widget.initiale == null ? 13 : 16,
            onTap: (_, point) => _centrerSur(point),
            onPositionChanged: (p, _) => _position = p.center,
          ),
          children: [
            TileLayer(
              urlTemplate: CovoiturageGeo.tuilesOpenStreetMap,
              userAgentPackageName: 'com.example.studenthub',
            ),
            RichAttributionWidget(
              attributions: const [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        const Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: 32),
            child: Icon(Icons.location_pin, color: Colors.red, size: 48),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: widget.choixVille
              ? _choixVille(context)
              : FilledButton.tonal(
                  onPressed: () =>
                      _centrerSur(CovoiturageGeo.centreZone(widget.zone)),
                  child: const Text('Centre de la zone'),
                ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 64, // laisse visible l'attribution OpenStreetMap
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Déplacez la carte pour placer le repère rouge sur le bon endroit.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _position),
                    child: const Text('Confirmer cette position'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
