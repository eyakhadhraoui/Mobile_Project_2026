import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/maintenance_options.dart';
import '../../core/routes/app_routes.dart';
import '../../models/demande_maintenance.dart';
import '../../models/user_model.dart';
import '../../providers/demande_provider.dart';
import '../../services/demande_service.dart';
import 'demande_form_screen.dart';

const _couleurFondVignette = Color(0xFFE8F0FA);

String _dateCourte(DateTime date) {
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${deux(date.day)}/${deux(date.month)}/${date.year}';
}

Color _couleurUrgence(String urgence) => switch (urgence) {
  'faible' => Colors.green,
  'moyenne' => Colors.orange,
  'elevee' => Colors.deepOrange,
  'critique' => Colors.red,
  _ => Colors.blueGrey,
};

Color _couleurStatut(StatutMaintenance statut) => switch (statut) {
  StatutMaintenance.enAttente => Colors.blueGrey,
  StatutMaintenance.enCours => const Color(0xFFB7791F),
  StatutMaintenance.terminee => Colors.green,
};

class DemandeListScreen extends StatefulWidget {
  const DemandeListScreen({super.key});

  @override
  State<DemandeListScreen> createState() => _DemandeListScreenState();
}

class _DemandeListScreenState extends State<DemandeListScreen> {
  final _rechercheController = TextEditingController();
  bool _filtresOuverts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reinitialiser();
    });
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  void _reinitialiser() {
    _rechercheController.clear();
    context.read<DemandeProvider>()
      ..setRecherche('')
      ..reinitialiserFiltres();
  }

  /// Une demande concerne toujours un logement loué par le locataire.
  Future<void> _ouvrirFormulaire() async {
    final provider = context.read<DemandeProvider>();
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);
    await provider.chargerLogements();
    if (provider.logements.isEmpty) {
      messager.showSnackBar(
        const SnackBar(
          content: Text(
            'Vous devez louer un logement pour créer une demande.',
          ),
        ),
      );
      return;
    }
    await navigateur.pushNamed(AppRoutes.maintenanceForm);
  }

  void _modifier(DemandeMaintenance demande) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DemandeFormScreen(demande: demande),
      ),
    );
  }

  Future<bool> _confirmer({
    required String titre,
    required String message,
    required String action,
  }) async {
    final reponse = await showDialog<bool>(
      context: context,
      builder: (dialogue) => AlertDialog(
        title: Text(titre),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogue).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogue).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return reponse ?? false;
  }

  Future<void> _supprimer(DemandeMaintenance demande) async {
    final provider = context.read<DemandeProvider>();
    final messager = ScaffoldMessenger.of(context);
    final confirme = await _confirmer(
      titre: 'Supprimer la demande ?',
      message: '« ${demande.title} » sera supprimée définitivement.',
      action: 'Supprimer',
    );
    if (!confirme) return;
    try {
      await provider.supprimer(demande.id);
      messager.showSnackBar(
        const SnackBar(content: Text('Demande supprimée')),
      );
    } on DemandeAccesRefuse catch (refus) {
      messager.showSnackBar(SnackBar(content: Text(refus.message)));
    } catch (_) {
      messager.showSnackBar(
        const SnackBar(content: Text('Erreur lors de la suppression')),
      );
    }
  }

  /// Exécute une mise à jour, puis affiche [succes] ou l'erreur adaptée.
  Future<void> _mettreAJour(
    ScaffoldMessengerState messager,
    Future<void> Function() action,
    String succes,
  ) async {
    try {
      await action();
      messager.showSnackBar(SnackBar(content: Text(succes)));
    } on DemandeAccesRefuse catch (refus) {
      messager.showSnackBar(SnackBar(content: Text(refus.message)));
    } catch (_) {
      messager.showSnackBar(
        const SnackBar(content: Text('Erreur lors de la mise à jour')),
      );
    }
  }

  Future<void> _marquerResolue(DemandeMaintenance demande) async {
    final provider = context.read<DemandeProvider>();
    final messager = ScaffoldMessenger.of(context);
    final confirme = await _confirmer(
      titre: 'Problème résolu ?',
      message: 'Marquer « ${demande.title} » comme terminée ?',
      action: 'Oui, résolu',
    );
    if (!confirme) return;
    await _mettreAJour(
      messager,
      () => provider.changerStatut(demande.id, StatutMaintenance.terminee),
      'Demande marquée comme résolue',
    );
  }

  Future<void> _changerStatut(DemandeMaintenance demande) async {
    final provider = context.read<DemandeProvider>();
    final messager = ScaffoldMessenger.of(context);
    final choix = await showModalBottomSheet<StatutMaintenance>(
      context: context,
      showDragHandle: true,
      builder: (feuille) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final statut in provider.statutsAutorises(demande))
              ListTile(
                title: Text(statut.label),
                trailing: statut == demande.statut
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(feuille).pop(statut),
              ),
          ],
        ),
      ),
    );
    if (choix == null || choix == demande.statut) return;
    await _mettreAJour(
      messager,
      () => provider.changerStatut(demande.id, choix),
      'Statut mis à jour',
    );
  }

  Future<void> _assigner(DemandeMaintenance demande) async {
    const aucun = '';
    final provider = context.read<DemandeProvider>();
    final messager = ScaffoldMessenger.of(context);
    final List<PrestataireDemande> prestataires;
    try {
      prestataires = await provider.listerPrestataires();
    } on DemandeAccesRefuse catch (refus) {
      messager.showSnackBar(SnackBar(content: Text(refus.message)));
      return;
    } catch (_) {
      messager.showSnackBar(
        const SnackBar(content: Text('Erreur lors de la mise à jour')),
      );
      return;
    }
    if (prestataires.isEmpty && demande.assigneeId == null) {
      messager.showSnackBar(
        const SnackBar(
          content: Text('Aucun prestataire disponible sur cet appareil.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    final choix = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (feuille) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Aucun prestataire'),
                trailing: demande.assigneeId == null
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(feuille).pop(aucun),
              ),
              for (final prestataire in prestataires)
                ListTile(
                  title: Text(prestataire.nom),
                  trailing: prestataire.id == demande.assigneeId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(feuille).pop(prestataire.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (choix == null) return;
    final cible = choix == aucun ? null : choix;
    if (cible == demande.assigneeId) return;
    await _mettreAJour(
      messager,
      () => provider.assigner(demande.id, cible),
      cible == null ? 'Assignation retirée' : 'Prestataire assigné',
    );
  }

  void _afficherDetails(DemandeMaintenance demande) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetailsDemande(demande: demande),
    );
  }

  String _titre(UserRole? role) => switch (role) {
    UserRole.prestataire => 'Mes interventions',
    UserRole.proprietaire ||
    UserRole.administrateur => 'Administration : demandes',
    _ => "Demandes d'intervention",
  };

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DemandeProvider>();
    final total = provider.demandes.length;
    final filtrees = provider.demandesFiltrees;
    return Scaffold(
      appBar: AppBar(title: Text(_titre(provider.role))),
      floatingActionButton: provider.peutCreer
          ? FloatingActionButton.extended(
              heroTag: 'maintenance_fab',
              onPressed: _ouvrirFormulaire,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle demande'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _barreRecherche(provider),
          if (_filtresOuverts) _panneauFiltres(provider),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                filtrees.length == total
                    ? '$total demande(s)'
                    : '${filtrees.length} sur $total demande(s)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(child: _corps(provider, filtrees)),
        ],
      ),
    );
  }

  Widget _barreRecherche(DemandeProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _rechercheController,
              onChanged: provider.setRecherche,
              decoration: InputDecoration(
                hintText: 'Rechercher (titre, description, nom...)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: provider.recherche.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _rechercheController.clear();
                          provider.setRecherche('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Filtres',
            onPressed: () =>
                setState(() => _filtresOuverts = !_filtresOuverts),
            icon: Badge(
              isLabelVisible: provider.nombreFiltresActifs > 0,
              label: Text('${provider.nombreFiltresActifs}'),
              child: const Icon(Icons.tune),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panneauFiltres(DemandeProvider provider) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.4,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titreFiltre('Statut'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tous'),
                  selected: provider.filtreStatut == null,
                  onSelected: (_) => provider.setFiltreStatut(null),
                ),
                for (final statut in StatutMaintenance.values)
                  ChoiceChip(
                    label: Text(statut.label),
                    selected: provider.filtreStatut == statut,
                    onSelected: (_) => provider.setFiltreStatut(statut),
                  ),
              ],
            ),
            _titreFiltre('Urgence'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Toutes'),
                  selected: provider.filtreUrgence == null,
                  onSelected: (_) => provider.setFiltreUrgence(null),
                ),
                for (final urgence in MaintenanceOptions.urgencies)
                  ChoiceChip(
                    label: Text(urgence.label),
                    selected: provider.filtreUrgence == urgence.value,
                    onSelected: (_) => provider.setFiltreUrgence(urgence.value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _listeDeroulante(
              label: 'Catégorie',
              options: MaintenanceOptions.categories,
              valeur: provider.filtreCategorie,
              onChanged: provider.setFiltreCategorie,
            ),
            const SizedBox(height: 12),
            _listeDeroulante(
              label: 'Pièce',
              options: MaintenanceOptions.rooms,
              valeur: provider.filtrePiece,
              onChanged: provider.setFiltrePiece,
            ),
            _titreFiltre('Trier par date'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Plus récentes'),
                  selected: provider.recentsDabord,
                  onSelected: (_) => provider.setRecentsDabord(true),
                ),
                ChoiceChip(
                  label: const Text('Plus anciennes'),
                  selected: !provider.recentsDabord,
                  onSelected: (_) => provider.setRecentsDabord(false),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _reinitialiser,
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Réinitialiser'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titreFiltre(String titre) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(titre, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  Widget _listeDeroulante({
    required String label,
    required List<OptionItem> options,
    required String? valeur,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String?>(
      key: ValueKey('$label-$valeur'),
      initialValue: valeur,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String?>(child: Text('Toutes')),
        for (final option in options)
          DropdownMenuItem<String?>(
            value: option.value,
            child: Text(option.label),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _corps(
    DemandeProvider provider,
    List<DemandeMaintenance> filtrees,
  ) {
    if (provider.demandes.isEmpty) {
      if (provider.chargement) {
        return const Center(child: CircularProgressIndicator());
      }
      if (provider.erreur != null) {
        return _message(
          texte: 'Impossible de charger les demandes.',
          action: FilledButton(
            onPressed: provider.charger,
            child: const Text('Réessayer'),
          ),
        );
      }
      return _message(
        icone: Icons.build_circle_outlined,
        texte: provider.role == UserRole.prestataire
            ? 'Aucune intervention assignée pour le moment.'
            : 'Aucune demande pour le moment.',
        detail: provider.peutCreer
            ? 'Appuie sur « Nouvelle demande » pour en créer une.'
            : null,
      );
    }
    if (filtrees.isEmpty) {
      return _message(
        icone: Icons.search_off,
        texte: 'Aucun résultat.',
        action: TextButton(
          onPressed: _reinitialiser,
          child: const Text('Réinitialiser la recherche et les filtres'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: provider.charger,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: filtrees.length,
        itemBuilder: (_, index) {
          final demande = filtrees[index];
          final modifiable = provider.peutModifier(demande);
          return _CarteDemande(
            key: ValueKey(demande.id),
            demande: demande,
            onTap: () =>
                modifiable ? _modifier(demande) : _afficherDetails(demande),
            onModifier: modifiable ? () => _modifier(demande) : null,
            onChangerStatut: provider.statutsAutorises(demande).isNotEmpty
                ? () => _changerStatut(demande)
                : null,
            onAssigner: provider.peutAssigner(demande)
                ? () => _assigner(demande)
                : null,
            onSupprimer: provider.peutSupprimer(demande)
                ? () => _supprimer(demande)
                : null,
            onResolue: provider.peutMarquerResolue(demande)
                ? () => _marquerResolue(demande)
                : null,
          );
        },
      ),
    );
  }

  Widget _message({
    IconData? icone,
    required String texte,
    String? detail,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null) ...[
              Icon(icone, size: 64, color: Colors.blueGrey),
              const SizedBox(height: 12),
            ],
            Text(texte, textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(detail, textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: 12),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

class _CarteDemande extends StatelessWidget {
  const _CarteDemande({
    super.key,
    required this.demande,
    required this.onTap,
    required this.onModifier,
    required this.onChangerStatut,
    required this.onAssigner,
    required this.onSupprimer,
    required this.onResolue,
  });

  final DemandeMaintenance demande;
  final VoidCallback onTap;
  final VoidCallback? onModifier;
  final VoidCallback? onChangerStatut;
  final VoidCallback? onAssigner;
  final VoidCallback? onSupprimer;
  final VoidCallback? onResolue;

  PopupMenuItem<VoidCallback> _action(
    VoidCallback action,
    IconData icone,
    String libelle,
  ) => PopupMenuItem(
    value: action,
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icone),
      title: Text(libelle),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (onModifier != null)
        _action(onModifier!, Icons.edit_outlined, 'Modifier'),
      if (onChangerStatut != null)
        _action(onChangerStatut!, Icons.sync_alt, 'Changer le statut'),
      if (onAssigner != null)
        _action(onAssigner!, Icons.person_add_alt, 'Assigner un prestataire'),
      if (onSupprimer != null)
        _action(onSupprimer!, Icons.delete_outline, 'Supprimer'),
    ];
    final textes = Theme.of(context).textTheme;
    final categorie = MaintenanceOptions.labelOf(
      MaintenanceOptions.categories,
      demande.category,
    );
    final piece = MaintenanceOptions.labelOf(
      MaintenanceOptions.rooms,
      demande.room,
    );
    final urgence = MaintenanceOptions.labelOf(
      MaintenanceOptions.urgencies,
      demande.urgency,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 12, actions.isEmpty ? 12 : 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Vignette(chemin: demande.photoPath),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      demande.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textes.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('$categorie • $piece', style: textes.bodySmall),
                    Text(
                      '${demande.residentName} • ${_dateCourte(demande.createdAt)}',
                      style: textes.bodySmall,
                    ),
                    if (demande.logementTitre != null)
                      Text(
                        'Logement : ${demande.logementTitre}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textes.bodySmall,
                      ),
                    if (demande.proprietaireNom != null)
                      Text(
                        'Propriétaire : ${demande.proprietaireNom}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textes.bodySmall,
                      ),
                    if (demande.assigneeNom != null)
                      Text(
                        'Assignée à : ${demande.assigneeNom}',
                        style: textes.bodySmall,
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Badge(
                          texte: urgence,
                          couleur: _couleurUrgence(demande.urgency),
                        ),
                        _Badge(
                          texte: demande.statut.label,
                          couleur: _couleurStatut(demande.statut),
                        ),
                      ],
                    ),
                    if (onResolue != null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: onResolue,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Marquer comme résolu'),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                PopupMenuButton<VoidCallback>(
                  onSelected: (action) => action(),
                  itemBuilder: (_) => actions,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette({required this.chemin});

  final String? chemin;

  static const _taille = 72.0;

  Widget get _vide => Container(
    width: _taille,
    height: _taille,
    color: _couleurFondVignette,
    child: const Icon(Icons.build_outlined),
  );

  @override
  Widget build(BuildContext context) {
    final photo = chemin;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: photo == null
          ? _vide
          : Image.file(
              File(photo),
              width: _taille,
              height: _taille,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _vide,
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.texte, required this.couleur});

  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(
          color: couleur,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _DetailsDemande extends StatelessWidget {
  const _DetailsDemande({required this.demande});

  final DemandeMaintenance demande;

  Widget _ligne(String libelle, String valeur) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            libelle,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(valeur)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final photo = demande.photoPath;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              demande.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (photo != null && File(photo).existsSync()) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(photo),
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (demande.logementTitre != null)
              _ligne('Logement', demande.logementTitre!),
            if (demande.proprietaireNom != null)
              _ligne('Propriétaire', demande.proprietaireNom!),
            _ligne('Statut', demande.statut.label),
            _ligne(
              'Urgence',
              MaintenanceOptions.labelOf(
                MaintenanceOptions.urgencies,
                demande.urgency,
              ),
            ),
            _ligne(
              'Catégorie',
              MaintenanceOptions.labelOf(
                MaintenanceOptions.categories,
                demande.category,
              ),
            ),
            _ligne(
              'Pièce',
              MaintenanceOptions.labelOf(
                MaintenanceOptions.rooms,
                demande.room,
              ),
            ),
            _ligne('Résident', demande.residentName),
            _ligne('Téléphone', demande.residentPhone),
            if (demande.assigneeNom != null)
              _ligne('Assignée à', demande.assigneeNom!),
            _ligne('Créée le', _dateCourte(demande.createdAt)),
            const Divider(),
            const Text(
              'Description',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(demande.description),
          ],
        ),
      ),
    );
  }
}
