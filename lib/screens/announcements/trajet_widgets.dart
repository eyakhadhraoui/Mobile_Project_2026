import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/annonce.dart';
import '../../models/trajet.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/trajet_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/geocodage_service.dart';

const _ink = Color(0xFF14263F);
const _blue = Color(0xFF0F3D75);
const _muted = Color(0xFF66748A);

/// Établissements fréquents, proposés comme raccourcis de recherche. Leur
/// position est toujours demandée à OpenStreetMap, jamais codée en dur.
const suggestionsUniversites = [
  'Faculté des Sciences de Tunis',
  'École Nationale d’Ingénieurs de Tunis',
  'Institut National des Sciences Appliquées et de Technologie',
  'Faculté de Médecine de Tunis',
  'École Supérieure de Commerce de Tunis',
  'Faculté des Sciences de Sfax',
  'Université de Sousse',
  'Faculté des Sciences de Monastir',
];

/// Bloc « Mon université » de la liste des annonces : choix, filtre
/// « à moins de N min » et tri par distance.
class BlocUniversite extends StatelessWidget {
  const BlocUniversite({super.key});

  @override
  Widget build(BuildContext context) {
    final trajets = context.watch<TrajetProvider>();
    final universite = trajets.universite;
    if (universite == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [Color(0xFF0A2E5C), Color(0xFF1F66B0)]),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => choisirUniversite(context),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Temps de trajet jusqu’à votre fac', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        SizedBox(height: 4),
                        Text('Choisissez votre université pour voir les durées à pied et en voiture.', style: TextStyle(color: Color(0xFFDCE8F6), fontSize: 12)),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.arrow_forward, size: 18, color: Color(0xFF0F3D75)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school_outlined, size: 18, color: _blue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(universite.nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: _ink)),
              ),
              TextButton(onPressed: () => choisirUniversite(context), child: const Text('Changer')),
            ],
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                avatar: Icon(trajets.modeFiltre == ModeTrajet.pied ? Icons.directions_walk : Icons.directions_car, size: 16),
                label: Text('Moins de ${trajets.dureeMax} min ${trajets.modeFiltre.libelle}'),
                selected: trajets.filtreActif,
                onSelected: (actif) => trajets.configurerFiltre(actif: actif),
              ),
              PopupMenuButton<(int, ModeTrajet)>(
                tooltip: 'Durée et mode',
                icon: const Icon(Icons.tune, size: 20, color: _blue),
                onSelected: (choix) => trajets.configurerFiltre(actif: true, minutes: choix.$1, mode: choix.$2),
                itemBuilder: (_) => [
                  for (final mode in ModeTrajet.values)
                    for (final minutes in const [10, 15, 20, 30, 45])
                      PopupMenuItem(value: (minutes, mode), child: Text('Moins de $minutes min ${mode.libelle}')),
                ],
              ),
              ChoiceChip(
                avatar: const Icon(Icons.near_me_outlined, size: 16),
                label: const Text('Plus proches'),
                selected: trajets.triDistance,
                onSelected: (_) => trajets.basculerTri(),
              ),
            ],
          ),
          if (trajets.calculEnCours && trajets.aLocaliser > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Calcul des trajets… ${trajets.localises}/${trajets.aLocaliser} logement(s) localisé(s)',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
            )
          else if (trajets.erreur != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Trajets incomplets : ${trajets.erreur} Les durées déjà calculées restent affichées.',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ),
                TextButton(
                  onPressed: () => trajets.reessayer(context.read<AnnonceProvider>().annonces),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          if (trajets.filtreActif)
            const Text('Le filtre ne garde que les logements localisés.', style: TextStyle(fontSize: 11, color: _muted)),
        ],
      ),
    );
  }
}

/// « 🚶 12 min · 🚗 6 min · 1,2 km » sous un logement.
/// Pastille des logements situés autour de la fac de l'étudiant.
class BadgeFacProche extends StatelessWidget {
  const BadgeFacProche({super.key, required this.annonce});
  final Annonce annonce;

  @override
  Widget build(BuildContext context) {
    final trajets = context.watch<TrajetProvider>();
    if (!trajets.presDeMaFac(annonce)) return const SizedBox.shrink();
    final distance = formatDistance(trajets.distanceFacKm(annonce)! * 1000);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.school, size: 15, color: _blue),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Près de votre fac · $distance',
              style: const TextStyle(fontSize: 12, color: _blue, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class LigneTrajet extends StatelessWidget {
  const LigneTrajet({super.key, required this.annonceId});
  final String annonceId;

  @override
  Widget build(BuildContext context) {
    final trajets = context.watch<TrajetProvider>();
    if (trajets.universite == null) return const SizedBox.shrink();
    final trajet = trajets.pour(annonceId);
    if (trajet == null) return const SizedBox.shrink();
    const style = TextStyle(fontSize: 12, color: _muted);
    final Widget contenu = switch (trajet.etat) {
      EtatTrajet.enAttente || EtatTrajet.calcul => const Row(children: [
        SizedBox.square(dimension: 11, child: CircularProgressIndicator(strokeWidth: 1.5)),
        SizedBox(width: 6),
        Text('Calcul du trajet…', style: style),
      ]),
      EtatTrajet.nonLocalise => const Text('Adresse non localisée : trajet inconnu', style: style),
      EtatTrajet.indisponible when trajet.pied == null && trajet.voiture == null =>
        const Text('Trajet indisponible pour le moment', style: style),
      _ => Wrap(
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (trajet.pied != null) _Duree(icone: Icons.directions_walk, trajet: trajet.pied!),
          if (trajet.voiture != null) _Duree(icone: Icons.directions_car, trajet: trajet.voiture!),
          if ((trajet.pied ?? trajet.voiture) case final reference?)
            Text(formatDistance(reference.distanceMetres), style: style),
          if (trajet.pied == null && trajet.voiture == null) const Text('Aucun itinéraire trouvé', style: style),
          if (trajet.approximatif) const Text('(approx.)', style: style),
        ],
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(Icons.school_outlined, size: 14, color: _blue),
          const SizedBox(width: 5),
          Expanded(child: contenu),
        ],
      ),
    );
  }
}

class _Duree extends StatelessWidget {
  const _Duree({required this.icone, required this.trajet});
  final IconData icone;
  final Trajet trajet;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icone, size: 15, color: _ink),
      const SizedBox(width: 2),
      Text(formatDuree(trajet.duree), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _ink)),
    ],
  );
}

/// Recherche de l'université (Nominatim) puis enregistrement dans le profil.
Future<void> choisirUniversite(BuildContext context) async {
  final userProvider = context.read<UserProvider>();
  final user = userProvider.user;
  if (user == null) return;
  final choix = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _RechercheUniversite(),
  );
  if (choix == null) return;
  final preferences = Map<String, dynamic>.from(user.preferences);
  if (choix is Universite) {
    preferences[Universite.clePreference] = choix.toMap();
  } else {
    preferences.remove(Universite.clePreference); // « Retirer mon université »
  }
  await userProvider.save(user.copyWith(preferences: preferences));
}

class _RechercheUniversite extends StatefulWidget {
  const _RechercheUniversite();
  @override
  State<_RechercheUniversite> createState() => _RechercheUniversiteState();
}

class _RechercheUniversiteState extends State<_RechercheUniversite> {
  final _texte = TextEditingController();
  final _geocodage = GeocodageService();
  Future<List<Coordonnees>>? _resultats;

  @override
  void dispose() {
    _texte.dispose();
    _geocodage.fermer();
    super.dispose();
  }

  void _chercher(String texte) {
    if (texte.trim().length < 3) return;
    _texte.text = texte;
    setState(() => _resultats = _geocodage.rechercher(texte));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Mon université', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: _texte,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _chercher,
              decoration: InputDecoration(
                hintText: 'Nom de l’établissement ou adresse',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _chercher(_texte.text)),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _resultats == null
                  ? ListView(
                      shrinkWrap: true,
                      children: [
                        for (final nom in suggestionsUniversites)
                          ListTile(dense: true, leading: const Icon(Icons.school_outlined), title: Text(nom), onTap: () => _chercher(nom)),
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.close),
                          title: const Text('Retirer mon université'),
                          onTap: () => Navigator.pop(context, false),
                        ),
                      ],
                    )
                  : FutureBuilder<List<Coordonnees>>(
                      future: _resultats,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                        }
                        if (snapshot.hasError) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Recherche indisponible (connexion ?). Réessayez.', textAlign: TextAlign.center),
                          );
                        }
                        final lieux = snapshot.data!;
                        if (lieux.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Aucun lieu trouvé. Essayez le nom complet ou la ville.', textAlign: TextAlign.center),
                          );
                        }
                        return ListView(
                          shrinkWrap: true,
                          children: [
                            for (final lieu in lieux)
                              ListTile(
                                leading: const Icon(Icons.place_outlined),
                                title: Text(lieu.libelle.split(',').first),
                                subtitle: Text(lieu.libelle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                                onTap: () => Navigator.pop(
                                  context,
                                  Universite(nom: lieu.libelle.split(',').first.trim(), lat: lieu.lat, lon: lieu.lon),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
