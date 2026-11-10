import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/covoiturage_trajet.dart';
import '../../models/enums_covoiturage.dart';
import '../../providers/covoiturage_provider.dart';
import '../../services/covoiturage_geo.dart';
import '../../services/geocodage_service.dart';
import 'choisir_position_screen.dart';
import 'covoiturage_screen.dart';

class TrajetFormScreen extends StatefulWidget {
  const TrajetFormScreen({super.key, this.trajet});
  final CovoiturageTrajet? trajet;
  @override
  State<TrajetFormScreen> createState() => _TrajetFormScreenState();
}

class _TrajetFormScreenState extends State<TrajetFormScreen> {
  final _form = GlobalKey<FormState>();
  late TypeTrajetEnum _type;
  late int _places;
  late String _zone;
  late DateTime _date;
  late TimeOfDay _heure;
  late final TextEditingController _depart, _arrivee, _prix, _commentaire;
  LatLng? _departPosition, _arriveePosition;
  final _geocodage = GeocodageService();

  /// Champs (true = départ, false = destination) dont le lieu est en cours de recherche.
  final _recherches = <bool>{};

  /// Dernier texte rempli depuis la carte : tout autre texte a été saisi à la main.
  final _remplisAuto = <bool, String>{};
  @override
  void initState() {
    super.initState();
    final t = widget.trajet;
    _type = t?.type ?? TypeTrajetEnum.offre;
    _places = t?.places ?? 1;
    _zone = t?.zone ?? 'Tunis';
    _date = t == null
        ? DateTime.now().add(const Duration(days: 1))
        : DateTime.parse(t.date);
    final h = (t?.heure ?? '08:00').split(':');
    _heure = TimeOfDay(hour: int.parse(h[0]), minute: int.parse(h[1]));
    _depart = TextEditingController(text: t?.depart ?? '');
    _arrivee = TextEditingController(text: t?.arrivee ?? '');
    _prix = TextEditingController(text: t?.prix?.toString() ?? '');
    _commentaire = TextEditingController(text: t?.commentaire ?? '');
    if (t?.departLat != null && t?.departLng != null) {
      _departPosition = LatLng(t!.departLat!, t.departLng!);
    }
    if (t?.arriveeLat != null && t?.arriveeLng != null) {
      _arriveePosition = LatLng(t!.arriveeLat!, t.arriveeLng!);
    }
  }

  @override
  void dispose() {
    _depart.dispose();
    _arrivee.dispose();
    _prix.dispose();
    _commentaire.dispose();
    _geocodage.fermer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.trajet != null;
    final verrouille = edit && widget.trajet!.statut != StatutTrajetEnum.ouvert;
    return Scaffold(
      appBar: AppBar(
        title: Text(edit ? 'Modifier le trajet' : 'Publier un trajet'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<TypeTrajetEnum>(
              segments: const [
                ButtonSegment(
                  value: TypeTrajetEnum.offre,
                  label: Text('Je conduis'),
                  icon: Icon(Icons.directions_car),
                ),
                ButtonSegment(
                  value: TypeTrajetEnum.demande,
                  label: Text('Je cherche'),
                  icon: Icon(Icons.person_search),
                ),
              ],
              selected: {_type},
              onSelectionChanged: edit
                  ? null
                  : (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 16),
            _champ(_depart, 'Départ', enabled: !verrouille),
            TextButton.icon(
              onPressed: verrouille ? null : () => _choisir(true),
              icon: const Icon(Icons.map_outlined),
              label: Text(_libelleCarte(true, _departPosition)),
            ),
            const SizedBox(height: 12),
            _champ(_arrivee, 'Destination', enabled: !verrouille),
            TextButton.icon(
              onPressed: verrouille ? null : () => _choisir(false),
              icon: const Icon(Icons.map_outlined),
              label: Text(_libelleCarte(false, _arriveePosition)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField(
              initialValue: _zone,
              decoration: const InputDecoration(labelText: 'Zone'),
              items: villesCovoiturage
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => _zone = v!),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: Text(
                'Date : ${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: _date,
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            ListTile(
              title: Text('Heure : ${_heure.format(context)}'),
              onTap: () async {
                final h = await showTimePicker(
                  context: context,
                  initialTime: _heure,
                );
                if (h != null) setState(() => _heure = h);
              },
            ),
            Row(
              children: [
                const Text('Places'),
                IconButton(
                  onPressed: _places > 1
                      ? () => setState(() => _places--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_places'),
                IconButton(
                  onPressed: () => setState(() => _places++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (_type == TypeTrajetEnum.offre) ...[
              const SizedBox(height: 8),
              _champ(
                _prix,
                'Participation aux frais (TND)',
                keyboard: TextInputType.number,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _commentaire,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Commentaire (facultatif)',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _recherches.isEmpty ? _enregistrer : null,
              child: Text(edit ? 'Enregistrer' : 'Publier le trajet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _champ(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    bool enabled = true,
  }) => TextFormField(
    controller: c,
    enabled: enabled,
    keyboardType: keyboard,
    // L'erreur disparaît dès que le champ est rempli, y compris depuis la carte.
    autovalidateMode: AutovalidateMode.onUserInteraction,
    decoration: InputDecoration(labelText: label),
    validator: (v) {
      if (v == null || v.trim().isEmpty) return '$label est obligatoire.';
      if (label.startsWith('Participation') &&
          (double.tryParse(v.replaceAll(',', '.')) == null ||
              double.parse(v.replaceAll(',', '.')) < 0)) {
        return 'Indiquez un prix valide.';
      }
      return null;
    },
  );
  Future<void> _choisir(bool depart) async {
    final pos = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => ChoisirPositionScreen(
          titre: depart ? 'Choisir le départ' : 'Choisir la destination',
          zone: _zone,
          initiale: depart ? _departPosition : _arriveePosition,
        ),
      ),
    );
    if (pos != null && mounted) {
      setState(() {
        if (depart) {
          _departPosition = pos;
        } else {
          _arriveePosition = pos;
        }
        _recherches.add(depart);
      });
      await _remplirDepuisCarte(depart, pos);
    }
  }

  String _libelleCarte(bool depart, LatLng? position) {
    if (_recherches.contains(depart)) return 'Recherche du lieu…';
    return position == null ? 'Choisir sur la carte' : 'Position choisie ✓';
  }

  /// Écrit le nom du lieu dans le champ, sans écraser un texte saisi à la main.
  Future<void> _remplirDepuisCarte(bool depart, LatLng pos) async {
    String? lieu;
    try {
      lieu = await _geocodage.lieuDe(pos.latitude, pos.longitude);
    } on GeocodageIndisponibleException {
      lieu = null;
    }
    // Un autre point a été choisi entre-temps : sa propre recherche s'en charge.
    if (!mounted || pos != (depart ? _departPosition : _arriveePosition)) {
      return;
    }
    setState(() => _recherches.remove(depart));
    final champ = depart ? _depart : _arrivee;
    if (champ.text.trim().isNotEmpty && champ.text != _remplisAuto[depart]) {
      return;
    }
    if (lieu != null) {
      champ.text = lieu;
      _remplisAuto[depart] = lieu;
      return;
    }
    champ.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Nom du lieu introuvable. Saisissez-le à la main.'),
      ),
    );
  }

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    final p = context.read<CovoiturageProvider>();
    final old = widget.trajet;
    final d = _departPosition ?? CovoiturageGeo.centreZone(_zone);
    final a = _arriveePosition ?? CovoiturageGeo.centreZone(_zone);
    final t = CovoiturageTrajet(
      id: old?.id ?? 't_${DateTime.now().microsecondsSinceEpoch}',
      auteurId: old?.auteurId ?? p.compte!.id,
      auteurNom: old?.auteurNom ?? p.compte!.nom,
      type: _type,
      depart: _depart.text.trim(),
      arrivee: _arrivee.text.trim(),
      zone: _zone,
      date:
          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
      heure:
          '${_heure.hour.toString().padLeft(2, '0')}:${_heure.minute.toString().padLeft(2, '0')}',
      places: _places,
      prix: _type == TypeTrajetEnum.offre
          ? double.parse(_prix.text.replaceAll(',', '.'))
          : null,
      commentaire: _commentaire.text.trim(),
      statut: old?.statut ?? StatutTrajetEnum.ouvert,
      departLat: d.latitude,
      departLng: d.longitude,
      arriveeLat: a.latitude,
      arriveeLng: a.longitude,
    );
    try {
      if (old == null) {
        await p.publier(t);
      } else {
        await p.modifier(old, t);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              old == null ? 'Trajet publié' : 'Trajet modifié avec succès',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(p.erreur ?? e.toString())));
      }
    }
  }
}
