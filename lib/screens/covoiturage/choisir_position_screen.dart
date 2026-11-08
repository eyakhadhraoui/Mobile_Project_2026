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
  });
  final String titre, zone;
  final LatLng? initiale;
  @override
  State<ChoisirPositionScreen> createState() => _ChoisirPositionScreenState();
}

class _ChoisirPositionScreenState extends State<ChoisirPositionScreen> {
  late LatLng _position =
      widget.initiale ?? CovoiturageGeo.centreZone(widget.zone);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.titre)),
    body: Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _position,
            initialZoom: 13,
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
          child: FilledButton.tonal(
            onPressed: () => setState(
              () => _position = CovoiturageGeo.centreZone(widget.zone),
            ),
            child: const Text('Centre de la zone'),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: FilledButton(
            onPressed: () => Navigator.pop(context, _position),
            child: const Text('Confirmer cette position'),
          ),
        ),
      ],
    ),
  );
}
