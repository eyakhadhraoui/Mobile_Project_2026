import 'package:flutter/material.dart';

import '../../services/estimation_prix_service.dart';

const _ink = Color(0xFF14263F);
const _gris = Color(0xFF66748A);
const _bord = Color(0xFFE4EAF2);

String montantEstime(double valeur) {
  final chiffres = valeur.toStringAsFixed(0);
  final tampon = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) tampon.write(' ');
    tampon.write(chiffres[i]);
  }
  return '$tampon DT';
}

/// Estimation d'un loyer ou d'un prix de vente. Ouvert depuis le formulaire
/// d'annonce avec [depuisAnnonce], l'écran renvoie le loyer retenu.
class EstimationPrixScreen extends StatefulWidget {
  const EstimationPrixScreen({
    super.key,
    this.service,
    this.depuisAnnonce = false,
    this.categorie = CategorieBien.appartement,
    this.ville = '',
    this.quartier = '',
    this.surface,
    this.chambres,
  });

  final EstimationPrixService? service;
  final bool depuisAnnonce;
  final CategorieBien categorie;
  final String ville;
  final String quartier;
  final double? surface;
  final int? chambres;

  @override
  State<EstimationPrixScreen> createState() => _EstimationPrixScreenState();
}

class _EstimationPrixScreenState extends State<EstimationPrixScreen> {
  final _form = GlobalKey<FormState>();
  late final _surface = TextEditingController(
    text: widget.surface == null ? '' : widget.surface!.toStringAsFixed(0),
  );
  late final _chambres = TextEditingController(text: widget.chambres?.toString() ?? '');
  final _sdb = TextEditingController();
  final _cleResultat = GlobalKey();

  EstimationPrixService? _service;
  TypeTransaction _type = TypeTransaction.louer;
  late CategorieBien _categorie = widget.categorie;
  String? _ville;
  String? _quartier;
  EstimationPrix? _resultat;

  @override
  void initState() {
    super.initState();
    final fourni = widget.service;
    if (fourni != null) {
      _preparer(fourni);
    } else {
      EstimationPrixService.charger().then((service) {
        if (mounted) setState(() => _preparer(service));
      });
    }
  }

  void _preparer(EstimationPrixService service) {
    _service = service;
    final lieu = service.resoudreLieu(_type, widget.ville, widget.quartier);
    _ville = lieu?.ville;
    _quartier = lieu?.quartier;
  }

  @override
  void dispose() {
    _surface.dispose();
    _chambres.dispose();
    _sdb.dispose();
    super.dispose();
  }

  void _changer(VoidCallback action) => setState(() {
    action();
    _resultat = null;
  });

  void _estimer(EstimationPrixService service) {
    if (!_form.currentState!.validate()) return;
    int? entier(TextEditingController c) => int.tryParse(c.text.trim());
    setState(() {
      _resultat = service.estimer(
        type: _type,
        categorie: _categorie,
        ville: _ville!,
        quartier: _quartier,
        surface: double.parse(_surface.text.trim().replaceAll(',', '.')),
        chambres: entier(_chambres),
        sdb: entier(_sdb),
      );
    });
    // Le résultat s'affiche sous le formulaire : on le fait apparaître.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cible = _cleResultat.currentContext;
      if (cible != null && cible.mounted) {
        Scrollable.ensureVisible(cible, duration: const Duration(milliseconds: 250), alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      }
    });
  }

  String? _valideSurface(String? valeur) {
    final surface = double.tryParse((valeur ?? '').trim().replaceAll(',', '.'));
    return surface == null || surface < 10 || surface > 1500 ? 'Entre 10 et 1500 m².' : null;
  }

  String? _valideOption(String? valeur, int max, {int min = 0}) {
    final texte = (valeur ?? '').trim();
    if (texte.isEmpty) return null;
    final nombre = int.tryParse(texte);
    return nombre == null || nombre < min || nombre > max ? 'Entre $min et $max.' : null;
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return Scaffold(
      appBar: AppBar(title: Text(widget.depuisAnnonce ? 'Estimer le loyer' : 'Estimer un prix')),
      body: service == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: _contenu(service)),
    );
  }

  Widget _contenu(EstimationPrixService service) {
    final categories = [
      (CategorieBien.appartement, 'Appartement'),
      (CategorieBien.maison, 'Maison ou villa'),
      if (_type == TypeTransaction.louer) (CategorieBien.colocation, 'Colocation'),
    ];
    final resultat = _resultat;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          if (!widget.depuisAnnonce) ...[
            SegmentedButton<TypeTransaction>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: TypeTransaction.louer, label: Text('Louer')),
                ButtonSegment(value: TypeTransaction.vendre, label: Text('Acheter')),
              ],
              selected: {_type},
              onSelectionChanged: (choix) => _changer(() {
                _type = choix.single;
                if (_type == TypeTransaction.vendre && _categorie == CategorieBien.colocation) {
                  _categorie = CategorieBien.appartement;
                }
                if (_ville != null && !service.villes(_type).contains(_ville)) _ville = null;
                if (_ville == null || !service.quartiers(_type, _ville!).contains(_quartier)) _quartier = null;
              }),
            ),
            const SizedBox(height: 14),
          ],
          DropdownButtonFormField<CategorieBien>(
            initialValue: _categorie,
            decoration: const InputDecoration(labelText: 'Type de bien'),
            items: [
              for (final (valeur, libelle) in categories) DropdownMenuItem(value: valeur, child: Text(libelle)),
            ],
            onChanged: (valeur) => _changer(() => _categorie = valeur!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('ville_${_type.name}_$_ville'),
            initialValue: _ville,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Ville'),
            items: [
              for (final ville in service.villes(_type)) DropdownMenuItem(value: ville, child: Text(ville)),
            ],
            validator: (valeur) => valeur == null ? 'Choisissez une ville.' : null,
            onChanged: (valeur) => _changer(() {
              _ville = valeur;
              _quartier = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey('quartier_${_type.name}_${_ville}_$_quartier'),
            initialValue: _quartier,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Quartier'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Toute la ville')),
              if (_ville != null)
                for (final quartier in service.quartiers(_type, _ville!))
                  DropdownMenuItem<String?>(value: quartier, child: Text(quartier, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (valeur) => _changer(() => _quartier = valeur),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _surface,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Surface (m²)'),
            validator: _valideSurface,
            onChanged: (_) => _changer(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _chambres,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Chambres'),
                  validator: (v) => _valideOption(v, 20),
                  onChanged: (_) => _changer(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _sdb,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Salles de bain'),
                  validator: (v) => _valideOption(v, 10, min: 1),
                  onChanged: (_) => _changer(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => _estimer(service),
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Estimer le prix'),
          ),
          if (resultat != null) ...[
            const SizedBox(height: 18),
            _Resultat(
              key: _cleResultat,
              resultat: resultat,
              type: _type,
              ville: _ville!,
              quartier: _quartier,
              valeursCourantes: _chambres.text.trim().isEmpty || _sdb.text.trim().isEmpty,
            ),
            if (widget.depuisAnnonce) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(resultat.prix),
                icon: const Icon(Icons.check),
                label: const Text('Utiliser ce loyer'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Resultat extends StatelessWidget {
  const _Resultat({
    super.key,
    required this.resultat,
    required this.type,
    required this.ville,
    required this.valeursCourantes,
    this.quartier,
  });
  final bool valeursCourantes;
  final EstimationPrix resultat;
  final TypeTransaction type;
  final String ville;
  final String? quartier;

  @override
  Widget build(BuildContext context) {
    final suffixe = type == TypeTransaction.louer ? ' / mois' : '';
    final (libelle, couleur) = switch (resultat.confiance) {
      ConfianceEstimation.bonne => ('Fiabilité bonne', const Color(0xFF2F855A)),
      ConfianceEstimation.moyenne => ('Fiabilité moyenne', const Color(0xFFB7791F)),
      ConfianceEstimation.faible => ('Fiabilité faible', const Color(0xFFC53030)),
    };
    final zone = resultat.quartierUtilise ? '$quartier, $ville' : ville;
    final erreur = (resultat.erreurMediane * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _bord),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Prix estimé', style: TextStyle(color: _gris, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            '${montantEstime(resultat.prix)}$suffixe',
            style: const TextStyle(color: _ink, fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Fourchette probable : ${montantEstime(resultat.bas)} à ${montantEstime(resultat.haut)}',
            style: const TextStyle(color: _ink),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: couleur.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
            child: Text(libelle, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          Text(
            'Basé sur ${resultat.comparables} annonce(s) à $zone.'
            '${resultat.quartierUtilise || quartier == null ? '' : ' Quartier trop peu représenté : la ville entière a été utilisée.'}'
            '${valeursCourantes ? ' Champs vides : valeurs courantes pour cette surface.' : ''}',
            style: const TextStyle(color: _gris, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'Ordre de grandeur issu de prix demandés dans des annonces, non datées. '
            'Écart habituel avec le prix réel : environ $erreur %.',
            style: const TextStyle(color: _gris, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
