import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/alerte_trajet.dart';
import '../../models/enums_covoiturage.dart';
import '../../providers/alerte_trajet_provider.dart';
import '../../providers/covoiturage_provider.dart';
import 'choisir_position_screen.dart';

class FormulaireAlerteScreen extends StatefulWidget {
  const FormulaireAlerteScreen({super.key});
  @override
  State<FormulaireAlerteScreen> createState() => _FormulaireAlerteScreenState();
}

class _FormulaireAlerteScreenState extends State<FormulaireAlerteScreen> {
  final f = GlobalKey<FormState>();
  final d = TextEditingController(),
      a = TextEditingController(),
      p = TextEditingController();
  TypeTrajetEnum type = TypeTrajetEnum.offre;
  CreneauAlerteEnum c = CreneauAlerteEnum.journee;
  int places = 1;
  final Set<int> jours = {};
  LatLng? positionDepart, positionArrivee;

  @override
  void dispose() {
    d.dispose();
    a.dispose();
    p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = context.read<CovoiturageProvider>().compte!;
    return Scaffold(
      appBar: AppBar(title: const Text('Créer une alerte')),
      body: Form(
        key: f,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: d,
              decoration: const InputDecoration(labelText: 'Départ'),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Départ obligatoire' : null,
            ),
            TextFormField(
              controller: a,
              decoration: const InputDecoration(labelText: 'Destination'),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Destination obligatoire' : null,
            ),
            Chip(label: Text('Zone : ${u.zone}')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _choisirPosition(true, u.zone),
              icon: const Icon(Icons.map_outlined),
              label: Text(
                positionDepart == null
                    ? 'Position de départ (facultative)'
                    : 'Position de départ choisie',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _choisirPosition(false, u.zone),
              icon: const Icon(Icons.map_outlined),
              label: Text(
                positionArrivee == null
                    ? 'Position d’arrivée (facultative)'
                    : 'Position d’arrivée choisie',
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<TypeTrajetEnum>(
              segments: const [
                ButtonSegment(
                  value: TypeTrajetEnum.offre,
                  label: Text('Offres'),
                ),
                ButtonSegment(
                  value: TypeTrajetEnum.demande,
                  label: Text('Demandes'),
                ),
              ],
              selected: {type},
              onSelectionChanged: (v) => setState(() => type = v.first),
            ),
            DropdownButtonFormField(
              initialValue: c,
              items: CreneauAlerteEnum.values
                  .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                  .toList(),
              onChanged: (v) => setState(() => c = v!),
            ),
            const SizedBox(height: 12),
            Text(
              'Jours souhaités (facultatif)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Wrap(
              spacing: 6,
              children:
                  [
                        (1, 'Lun'),
                        (2, 'Mar'),
                        (3, 'Mer'),
                        (4, 'Jeu'),
                        (5, 'Ven'),
                        (6, 'Sam'),
                        (7, 'Dim'),
                      ]
                      .map(
                        (jour) => FilterChip(
                          label: Text(jour.$2),
                          selected: jours.contains(jour.$1),
                          onSelected: (selection) => setState(() {
                            if (selection) {
                              jours.add(jour.$1);
                            } else {
                              jours.remove(jour.$1);
                            }
                          }),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Places minimum : '),
                IconButton(
                  onPressed: places > 1 ? () => setState(() => places--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$places'),
                IconButton(
                  onPressed: () => setState(() => places++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (type == TypeTrajetEnum.offre)
              TextFormField(
                controller: p,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Prix maximum TND',
                ),
              ),
            FilledButton(
              onPressed: () async {
                if (!f.currentState!.validate()) {
                  return;
                }
                final al = AlerteTrajet(
                  id: 'a_${DateTime.now().microsecondsSinceEpoch}',
                  userId: u.id,
                  depart: d.text,
                  arrivee: a.text,
                  zone: u.zone,
                  typeCible: type,
                  creneau: c,
                  jours: jours.toList()..sort(),
                  places: places,
                  prixMax: p.text.isEmpty ? null : double.tryParse(p.text),
                  dateCreation: DateTime.now().toIso8601String(),
                  departLat: positionDepart?.latitude,
                  departLng: positionDepart?.longitude,
                  arriveeLat: positionArrivee?.latitude,
                  arriveeLng: positionArrivee?.longitude,
                );
                final provider = context.read<AlerteTrajetProvider>();
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                try {
                  await provider.enregistrer(al);
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Alerte créée')),
                  );
                  navigator.pop();
                } catch (e) {
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              child: const Text('Enregistrer l’alerte'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _choisirPosition(bool depart, String zone) async {
    final position = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => ChoisirPositionScreen(
          titre: depart ? 'Choisir le départ' : 'Choisir l’arrivée',
          zone: zone,
          initiale: depart ? positionDepart : positionArrivee,
        ),
      ),
    );
    if (!mounted || position == null) return;
    setState(() {
      if (depart) {
        positionDepart = position;
      } else {
        positionArrivee = position;
      }
    });
  }
}
