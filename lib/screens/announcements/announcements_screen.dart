import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/annonce.dart';
import '../../providers/annonce_provider.dart';
import '../../models/trajet.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trajet_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/api_client.dart';
import '../../services/heure_service.dart';
import 'announcement_notifications_screen.dart';
import 'housing_actions.dart';
import 'housing_requests_screen.dart';
import 'trajet_widgets.dart';

const _ink = Color(0xFF102A43);
const _blue = Color(0xFF326D98);
const _pale = Color(0xFFF3F8FD);
const _border = Color(0xFFD7E3EF);
const _muted = Color(0xFF52677B);

String _messageErreur(Object error) =>
    error is ApiException ? error.message : 'Une erreur est survenue.';

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  static const _filtres = [
    'Tout',
    'Logement',
    'Résidence',
    'Événement',
    'Avis',
    'Autre',
    'Mes annonces',
  ];
  static const _aModerer = 'À modérer';
  String _filtre = 'Tout';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnnonceProvider>();
    final userId = context.watch<AuthProvider>().currentUserId;
    final user = context.watch<UserProvider>().user;
    final prenom = user?.prenom ?? '';
    final trajets = context.watch<TrajetProvider>();
    // Université du profil et calcul des trajets (sans effet si rien n'a changé).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      trajets.definirUniversite(
        Universite.depuisPreferences(user?.preferences),
        provider.annonces,
      );
      trajets.calculer(provider.annonces);
    });
    final filtres = [..._filtres, if (provider.estAdmin) _aModerer];
    final filtre = filtres.contains(_filtre) ? _filtre : 'Tout';
    // Les listes publiques n'affichent que les annonces publiées ; « Mes annonces »
    // montre aussi les annonces programmées, en attente ou archivées (avec badge).
    final filtrees = provider.annonces.where((a) {
      return switch (filtre) {
        'Tout' => a.estPubliee,
        'Mes annonces' => a.proprietaireId == userId,
        _aModerer => a.statut == StatutAnnonce.enAttente,
        _ => a.estPubliee && a.categorie == filtre,
      };
    }).toList();
    // Filtre « à moins de N min » et tri par distance à l'université.
    final affichees = trajets.appliquer(filtrees);

    return Scaffold(
      backgroundColor: _pale,
      appBar: AppBar(
        backgroundColor: _pale,
        titleSpacing: 18,
        title: const Row(
          children: [
            Icon(Icons.home_outlined, color: _blue),
            SizedBox(width: 12),
            Text(
              'StudentHub',
              style: TextStyle(color: _ink, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Visites et demandes',
            icon: const Icon(Icons.event_note_outlined, color: _blue),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HousingRequestsScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Activité des annonces',
            icon: const Icon(Icons.notifications_outlined, color: _blue),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AnnouncementNotificationsScreen(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'annonces_fab',
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        tooltip: 'Nouvelle annonce',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AnnonceFormScreen()),
        ),
        child: const Icon(Icons.add, size: 30),
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.charger().catchError((_) {}),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 90),
          children: [
            Text(
              prenom.isEmpty ? 'Bonjour !' : 'Bonjour, $prenom !',
              style: const TextStyle(fontSize: 23, color: _ink),
            ),
            const SizedBox(height: 14),
            const BlocUniversite(),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Annonces',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _filtre = 'Tout'),
                  child: const Text('Voir tout'),
                ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filtres
                    .map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            f == _aModerer
                                ? '$f (${provider.aModerer})'
                                : f == 'Événement'
                                ? 'Événements'
                                : f,
                          ),
                          selected: filtre == f,
                          onSelected: (_) => setState(() => _filtre = f),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
            if (provider.erreur != null)
              _Bandeau(
                icon: Icons.cloud_off,
                couleur: const Color(0xFFC53030),
                texte: provider.horsLigne && provider.annonces.isNotEmpty
                    ? 'Hors ligne : annonces enregistrées sur l’appareil. ${_messageErreur(provider.erreur!)}'
                    : _messageErreur(provider.erreur!),
                action:
                    provider.erreur is ApiException &&
                        (provider.erreur as ApiException).status == 401
                    ? TextButton(
                        onPressed: () => context.read<AuthProvider>().signOut(),
                        child: const Text('Se reconnecter'),
                      )
                    : TextButton(
                        onPressed: () => provider.charger().catchError((_) {}),
                        child: const Text('Réessayer'),
                      ),
              ),
            if (provider.chargement && provider.annonces.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (affichees.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    'Aucune annonce pour le moment.',
                    style: TextStyle(color: _muted),
                  ),
                ),
              ),
            ...affichees.map(
              (a) =>
                  _AnnonceCard(annonce: a, estMoi: a.proprietaireId == userId),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnonceCard extends StatelessWidget {
  const _AnnonceCard({required this.annonce, required this.estMoi});
  final Annonce annonce;
  final bool estMoi;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: _border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AnnouncementDetailScreen(annonceId: annonce.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EnTete(annonce: annonce, estMoi: estMoi),
            if (!annonce.estPubliee) ...[
              const SizedBox(height: 8),
              _StatutBadge(annonce),
            ],
            const SizedBox(height: 10),
            Text(
              annonce.titre,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            if (annonce.estLogement) ...[
              const SizedBox(height: 4),
              _ResumeLogement(annonce),
              LigneTrajet(annonceId: annonce.id),
            ],
            const SizedBox(height: 5),
            Text(
              annonce.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, height: 1.35),
            ),
            const SizedBox(height: 10),
            _Galerie(annonce.photos, hauteur: 96),
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: annonce.aimeParMoi ? 'Je n’aime plus' : 'J’aime',
                  onPressed: annonce.estPubliee
                      ? () => _basculerLike(context, annonce)
                      : null,
                  icon: Icon(
                    annonce.aimeParMoi ? Icons.favorite : Icons.favorite_border,
                    color: annonce.aimeParMoi ? Colors.red : _muted,
                  ),
                ),
                Text('${annonce.likes}', style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 10),
                const Icon(
                  Icons.mode_comment_outlined,
                  size: 18,
                  color: _muted,
                ),
                const SizedBox(width: 5),
                Text(
                  '${annonce.nbCommentaires}',
                  style: const TextStyle(fontSize: 12),
                ),
                const Spacer(),
                if (annonce.nbAvis > 0) ...[
                  const Icon(Icons.star, size: 16, color: Color(0xFFE5A400)),
                  const SizedBox(width: 3),
                  Text(
                    '${_note(annonce.noteMoyenne)} (${annonce.nbAvis})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _basculerLike(BuildContext context, Annonce annonce) async {
  try {
    await context.read<AnnonceProvider>().basculerLike(annonce);
  } catch (error) {
    if (context.mounted) _snack(context, _messageErreur(error));
  }
}

// ---------------------------------------------------------------------------
// Détail
// ---------------------------------------------------------------------------

class AnnouncementDetailScreen extends StatefulWidget {
  const AnnouncementDetailScreen({super.key, required this.annonceId});
  final String annonceId;
  @override
  State<AnnouncementDetailScreen> createState() =>
      _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState extends State<AnnouncementDetailScreen> {
  final _commentaire = TextEditingController();
  List<CommentaireAnnonce>? _commentaires;
  String? _erreurCommentaires;
  bool _envoi = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _chargerCommentaires();
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _chargerCommentaires(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _commentaire.dispose();
    super.dispose();
  }

  Future<void> _chargerCommentaires() async {
    try {
      final commentaires = await context.read<AnnonceProvider>().commentaires(
        widget.annonceId,
      );
      if (mounted) {
        setState(() {
          _commentaires = commentaires;
          _erreurCommentaires = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _erreurCommentaires = _messageErreur(error));
    }
  }

  Future<void> _envoyerCommentaire() async {
    final texte = _commentaire.text.trim();
    if (texte.isEmpty || _envoi) return;
    setState(() => _envoi = true);
    try {
      final commentaires = await context.read<AnnonceProvider>().commenter(
        widget.annonceId,
        texte,
      );
      if (!mounted) return;
      _commentaire.clear();
      setState(() => _commentaires = commentaires);
    } catch (error) {
      if (mounted) _snack(context, _messageErreur(error));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _executer(
    Future<void> Function() action,
    String succes, {
    bool fermer = false,
  }) async {
    try {
      await action();
      if (!mounted) return;
      _snack(context, succes);
      if (fermer) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _snack(context, _messageErreur(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnnonceProvider>();
    final annonce = provider.parId(widget.annonceId);
    final userId = context.watch<AuthProvider>().currentUserId;
    if (annonce == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Annonce')),
        body: const Center(
          child: Text('Cette annonce n’existe plus ou n’est plus visible.'),
        ),
      );
    }
    final proprietaire = annonce.proprietaireId == userId;
    final admin = provider.estAdmin;

    return Scaffold(
      backgroundColor: _pale,
      appBar: AppBar(
        backgroundColor: _pale,
        title: const Text('Annonce'),
        actions: [
          if (proprietaire || admin)
            _menu(annonce, proprietaire: proprietaire, admin: admin),
        ],
      ),
      body: Column(
        children: [
          if (provider.operationEnCours)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                _EnTete(annonce: annonce, estMoi: proprietaire),
                if (!annonce.estPubliee) ...[
                  const SizedBox(height: 10),
                  _StatutBadge(annonce, detaille: true),
                ],
                if (admin && annonce.statut == StatutAnnonce.enAttente) ...[
                  const SizedBox(height: 10),
                  _moderation(annonce),
                ],
                const SizedBox(height: 12),
                Text(
                  annonce.titre,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _Galerie(annonce.photos, hauteur: 160),
                const SizedBox(height: 8),
                Text(annonce.description, style: const TextStyle(height: 1.4)),
                if (annonce.estLogement) ...[
                  const SizedBox(height: 14),
                  _DetailsLogement(annonce),
                  LigneTrajet(annonceId: annonce.id),
                ],
                if (annonce.estPubliee) ...[
                  const SizedBox(height: 14),
                  _avis(annonce, proprietaire: proprietaire),
                  const SizedBox(height: 16),
                  _sectionCommentaires(annonce),
                ],
              ],
            ),
          ),
          if (annonce.estLogement && annonce.estPubliee)
            _boutonsLogement(annonce, proprietaire),
          if (annonce.estPubliee && annonce.autoriserCommentaires)
            _saisieCommentaire(),
        ],
      ),
    );
  }

  Widget _menu(
    Annonce annonce, {
    required bool proprietaire,
    required bool admin,
  }) => PopupMenuButton<String>(
    onSelected: (choix) async {
      final provider = context.read<AnnonceProvider>();
      switch (choix) {
        case 'modifier':
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AnnonceFormScreen(initiale: annonce),
            ),
          );
        case 'archiver':
          await _executer(
            () => provider.changerStatut(annonce.id, StatutAnnonce.archivee),
            'Annonce archivée.',
          );
        case 'republier':
          final directe = admin || !provider.moderation;
          await _executer(
            () => provider.changerStatut(
              annonce.id,
              directe ? StatutAnnonce.publiee : StatutAnnonce.enAttente,
            ),
            directe ? 'Annonce publiée.' : 'Annonce renvoyée en validation.',
          );
        case 'publier':
          await _executer(
            () => provider.changerStatut(annonce.id, StatutAnnonce.publiee),
            'Annonce publiée.',
          );
        case 'reprogrammer':
          await _reprogrammer(annonce);
        case 'annuler_programmation':
          await _annulerProgrammation(annonce);
        case 'supprimer':
          if (await _confirmer(
            'Supprimer cette annonce ?',
            'Les photos, likes, commentaires et avis seront supprimés.',
          )) {
            await _executer(
              () => provider.supprimer(annonce.id),
              'Annonce supprimée.',
              fermer: true,
            );
          }
      }
    },
    itemBuilder: (_) => [
      if (proprietaire)
        const PopupMenuItem(value: 'modifier', child: Text('Modifier')),
      if (proprietaire && annonce.estProgrammee) ...const [
        PopupMenuItem(
          value: 'reprogrammer',
          child: Text('Modifier la programmation'),
        ),
        PopupMenuItem(
          value: 'annuler_programmation',
          child: Text('Annuler la programmation'),
        ),
      ],
      if (proprietaire &&
          annonce.statut == StatutAnnonce.enAttente &&
          !context.read<AnnonceProvider>().moderation)
        const PopupMenuItem(
          value: 'publier',
          child: Text('Publier maintenant'),
        ),
      if ((proprietaire || admin) && annonce.statut != StatutAnnonce.archivee)
        const PopupMenuItem(value: 'archiver', child: Text('Archiver')),
      if (proprietaire && annonce.statut == StatutAnnonce.archivee)
        const PopupMenuItem(value: 'republier', child: Text('Republier')),
      const PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
    ],
  );

  /// Nouvelle date choisie, vérifiée avec l'heure officielle, puis confirmée.
  Future<void> _reprogrammer(Annonce annonce) async {
    final heure = context.read<HeureService>();
    final provider = context.read<AnnonceProvider>();
    final date = await choisirDateHeurePublication(
      context,
      annonce.datePublication,
    );
    if (date == null || !mounted) return;
    final erreur = await verifierDateFuture(heure, date);
    if (!mounted) return;
    if (erreur != null) return _snack(context, erreur);
    if (!await _confirmer(
      'Modifier la programmation ?',
      'Nouvelle date de publication : ${formatDateHeure(date)}.',
    ))
      return;
    await _executer(
      () => provider.programmer(annonce, date),
      'Publication programmée le ${formatDateHeure(date)}.',
    );
  }

  /// Annulation confirmée : publier maintenant ou garder l'annonce en attente.
  Future<void> _annulerProgrammation(Annonce annonce) async {
    final provider = context.read<AnnonceProvider>();
    final validation = provider.moderation && !provider.estAdmin;
    final publier = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la programmation ?'),
        content: Text(
          validation
              ? '« Envoyer en validation » la soumet tout de suite aux administrateurs. '
                    '« Garder en attente » la laisse invisible pour les autres.'
              : '« Publier maintenant » la rend visible tout de suite. '
                    '« Garder en attente » la laisse invisible pour les autres.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Retour'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Garder en attente'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              validation ? 'Envoyer en validation' : 'Publier maintenant',
            ),
          ),
        ],
      ),
    );
    if (publier == null || !mounted) return;
    await _executer(
      () =>
          provider.annulerProgrammation(annonce.id, publierMaintenant: publier),
      !publier
          ? 'Programmation annulée : annonce en attente.'
          : validation
          ? 'Programmation annulée : annonce envoyée en validation.'
          : 'Programmation annulée : annonce publiée.',
    );
  }

  Future<bool> _confirmer(String titre, String texte) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titre),
          content: Text(texte),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;

  Widget _moderation(Annonce annonce) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4DE),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Modération', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Cette annonce attend votre validation avant d’être visible par tous.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _executer(
                () => context.read<AnnonceProvider>().changerStatut(
                  annonce.id,
                  StatutAnnonce.publiee,
                ),
                'Annonce publiée.',
              ),
              icon: const Icon(Icons.check),
              label: const Text('Publier'),
            ),
            OutlinedButton.icon(
              onPressed: () => _refuser(annonce),
              icon: const Icon(Icons.block),
              label: const Text('Refuser'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _refuser(Annonce annonce) async {
    final motif = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refuser l’annonce'),
        content: TextField(
          controller: motif,
          maxLength: 300,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motif (visible par l’auteur)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    final texte = motif.text.trim();
    motif.dispose();
    if (ok != true || !mounted) return;
    await _executer(
      () => context.read<AnnonceProvider>().changerStatut(
        annonce.id,
        StatutAnnonce.archivee,
        motif: texte,
      ),
      'Annonce refusée.',
    );
  }

  Widget _avis(Annonce annonce, {required bool proprietaire}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFDCEBFC),
      borderRadius: BorderRadius.circular(17),
    ),
    child: Row(
      children: [
        Text(
          annonce.nbAvis == 0 ? '–' : _note(annonce.noteMoyenne),
          style: const TextStyle(fontSize: 29),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Etoiles(annonce.noteMoyenne),
              Text(
                annonce.nbAvis == 0
                    ? 'Aucun avis pour le moment'
                    : 'Basé sur ${annonce.nbAvis} avis${annonce.maNote != null ? ' · votre note : ${annonce.maNote}/5' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        if (!proprietaire)
          FilledButton(
            onPressed: () => _noter(annonce),
            child: Text(annonce.maNote == null ? 'Donner un avis' : 'Modifier'),
          ),
      ],
    ),
  );

  Future<void> _noter(Annonce annonce) async {
    var note = annonce.maNote ?? 0;
    final choisie = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, update) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Donner un avis',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (i) => IconButton(
                      tooltip: '${i + 1}/5',
                      onPressed: () => update(() => note = i + 1),
                      icon: Icon(
                        i < note ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 34,
                      ),
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: note == 0 ? null : () => Navigator.pop(ctx, note),
                  child: const Text('Envoyer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choisie == null || !mounted) return;
    await _executer(
      () => context.read<AnnonceProvider>().noter(annonce.id, choisie),
      'Merci pour votre avis !',
    );
  }

  Widget _sectionCommentaires(Annonce annonce) {
    final commentaires = _commentaires;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Commentaires (${commentaires?.length ?? annonce.nbCommentaires})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (!annonce.autoriserCommentaires)
          const Text(
            'L’auteur a désactivé les commentaires.',
            style: TextStyle(color: _muted),
          ),
        if (_erreurCommentaires != null && commentaires == null)
          Text(
            _erreurCommentaires!,
            style: const TextStyle(color: Color(0xFFC53030)),
          ),
        if (commentaires == null && _erreurCommentaires == null)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          ),
        ...?commentaires?.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(c.auteur),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.auteur}${c.date == null ? '' : ' · ${_quand(c.date!)}'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(c.texte),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _boutonsLogement(Annonce annonce, bool proprietaire) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: proprietaire
          ? SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HousingRequestsScreen(initialTab: 2),
                  ),
                ),
                icon: const Icon(Icons.calendar_month),
                label: const Text('Gérer mes disponibilités'),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => HousingActions.bookVisit(context, annonce),
                    icon: const Icon(Icons.event_available),
                    label: const Text('Réserver une visite'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => HousingActions.rent(context, annonce),
                    icon: const Icon(Icons.key),
                    label: const Text('Demander la location'),
                  ),
                ),
              ],
            ),
    ),
  );

  Widget _saisieCommentaire() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentaire,
              maxLength: 2000,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _envoyerCommentaire(),
              decoration: InputDecoration(
                hintText: 'Écrire un commentaire…',
                counterText: '',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Envoyer',
            onPressed: _envoi ? null : _envoyerCommentaire,
            icon: _envoi
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Création / modification
// ---------------------------------------------------------------------------

class AnnonceFormScreen extends StatefulWidget {
  const AnnonceFormScreen({super.key, this.initiale});
  final Annonce? initiale;
  @override
  State<AnnonceFormScreen> createState() => _AnnonceFormScreenState();
}

class _AnnonceFormScreenState extends State<AnnonceFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Annonce? _init = widget.initiale;
  late final _titre = TextEditingController(text: _init?.titre);
  late final _description = TextEditingController(text: _init?.description);
  late final _loyer = TextEditingController(text: _nombre(_init?.loyer));
  late final _surface = TextEditingController(text: _nombre(_init?.surface));
  late final _chambres = TextEditingController(
    text: _init == null || !_init.estLogement ? '' : '${_init.chambres}',
  );
  late final _etage = TextEditingController(
    text: _init?.etage?.toString() ?? '',
  );
  late final _ville = TextEditingController(text: _init?.ville);
  late final _quartier = TextEditingController(text: _init?.quartier);
  late final _adresse = TextEditingController(text: _init?.adresse);
  late String _categorie = _init?.categorie ?? 'Logement';
  late String? _type = (_init?.typeLocation.isEmpty ?? true)
      ? null
      : _init!.typeLocation;
  late bool _commentaires = _init?.autoriserCommentaires ?? true;
  late final List<String> _photos = [...?_init?.photos];
  bool _envoi = false;

  /// Publication programmée : date et heure locales choisies par le propriétaire.
  late bool _programmer = _init?.estProgrammee ?? false;
  late DateTime? _datePublication = (_init?.estProgrammee ?? false)
      ? _init!.datePublication?.toLocal()
      : null;
  String? _erreurDate;
  bool _permissionsDemandees = false;

  static String _nombre(double? v) => v == null || v == 0
      ? ''
      : (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');

  @override
  void dispose() {
    for (final c in [
      _titre,
      _description,
      _loyer,
      _surface,
      _chambres,
      _etage,
      _ville,
      _quartier,
      _adresse,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _logement => _categorie == 'Logement';

  Future<void> _enregistrer() async {
    if (_envoi || !_form.currentState!.validate()) return;
    final provider = context.read<AnnonceProvider>();
    final heure = context.read<HeureService>();
    final userId = context.read<AuthProvider>().currentUserId ?? '';
    if (_programmer) {
      final date = _datePublication;
      if (date == null) {
        setState(
          () => _erreurDate = 'Choisissez la date et l’heure de publication.',
        );
        return;
      }
      // La date doit être dans le futur selon l'heure officielle, pas seulement
      // selon l'horloge du téléphone (qui peut être mal réglée).
      setState(() => _envoi = true);
      final erreur = await verifierDateFuture(heure, date);
      if (!mounted) return;
      if (erreur != null) {
        setState(() {
          _erreurDate = erreur;
          _envoi = false;
        });
        _snack(context, erreur);
        return;
      }
    }
    double decimal(TextEditingController c) =>
        double.parse(c.text.trim().replaceAll(',', '.'));
    final annonce = Annonce(
      id: _init?.id ?? '',
      categorie: _categorie,
      titre: _titre.text.trim(),
      description: _description.text.trim(),
      typeLocation: _logement ? _type! : '',
      loyer: _logement ? decimal(_loyer) : 0,
      surface: _logement ? decimal(_surface) : 0,
      chambres: _logement ? int.parse(_chambres.text.trim()) : 0,
      etage: _logement && _etage.text.trim().isNotEmpty
          ? int.parse(_etage.text.trim())
          : null,
      ville: _logement ? _ville.text.trim() : '',
      quartier: _logement ? _quartier.text.trim() : '',
      adresse: _logement ? _adresse.text.trim() : '',
      photos: _photos,
      proprietaireId: _init?.proprietaireId ?? userId,
      autoriserCommentaires: _commentaires,
      // Avec une date, le serveur enregistre l'annonce au statut « programmee » ;
      // sans date, elle est publiée (ou envoyée en validation si la modération est active).
      datePublication: _programmer ? _datePublication : null,
    );
    setState(() => _envoi = true);
    try {
      final resultat = _init == null
          ? await provider.ajouter(annonce)
          : await provider.modifier(annonce);
      if (!mounted) return;
      _snack(context, switch (resultat.statut) {
        StatutAnnonce.publiee =>
          _init == null ? 'Annonce publiée.' : 'Annonce modifiée.',
        StatutAnnonce.enAttente => 'Annonce enregistrée : elle sera visible après validation par un administrateur.',
        StatutAnnonce.archivee =>
          'Annonce modifiée (toujours archivée : republiez-la depuis le menu).',
        StatutAnnonce.programmee =>
          'Annonce programmée : publication le ${formatDateHeure(resultat.datePublication ?? _datePublication!)}.',
      });
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _snack(context, _messageErreur(error));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  /// Interrupteur « Programmer la publication ».
  Future<void> _basculerProgrammation(bool active) async {
    if (active) {
      final date = await choisirDateHeurePublication(context, _datePublication);
      if (date == null || !mounted) return;
      setState(() {
        _programmer = true;
        _datePublication = date;
        _erreurDate = null;
      });
      await _demanderPermissions();
      return;
    }
    if (_init?.estProgrammee ?? false) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Annuler la programmation ?'),
          content: const Text(
            'À l’enregistrement, l’annonce sera publiée tout de suite '
            '(ou envoyée en validation si la modération est active).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Garder la date'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Annuler la programmation'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _programmer = false;
      _erreurDate = null;
    });
  }

  Future<void> _changerDate() async {
    final date = await choisirDateHeurePublication(context, _datePublication);
    if (date == null || !mounted) return;
    setState(() {
      _datePublication = date;
      _erreurDate = null;
    });
  }

  /// Notifications et alarmes exactes : demandées une fois, à la première programmation.
  Future<void> _demanderPermissions() async {
    if (_permissionsDemandees) return;
    _permissionsDemandees = true;
    final accordees = await context
        .read<AnnonceProvider>()
        .demanderPermissionsNotifications();
    if (!accordees && mounted) {
      _snack(
        context,
        'Notifications désactivées : l’annonce sera tout de même publiée à l’heure prévue '
        '(vérifiée aussi à chaque ouverture de l’application).',
      );
    }
  }

  Future<void> _ajouterPhotos() async {
    final restantes = 6 - _photos.length;
    if (restantes <= 0) return;
    try {
      final picker = ImagePicker();
      final choisies = restantes == 1
          ? [
              ?await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
                maxWidth: 1920,
              ),
            ]
          : await picker.pickMultiImage(
              limit: restantes,
              imageQuality: 85,
              maxWidth: 1920,
            );
      if (!mounted || choisies.isEmpty) return;
      setState(() {
        for (final photo in choisies) {
          if (_photos.length >= 6) break;
          if (!_photos.contains(photo.path)) _photos.add(photo.path);
        }
      });
    } catch (_) {
      if (mounted) _snack(context, 'Impossible d’ouvrir la galerie.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _pale,
    appBar: AppBar(
      backgroundColor: _pale,
      title: Text(_init == null ? 'Nouvelle annonce' : 'Modifier l’annonce'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: AbsorbPointer(
      absorbing: _envoi,
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          children: [
            const Text('Catégorie'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: Annonce.categories
                  .map(
                    (c) => ChoiceChip(
                      label: Text(c),
                      selected: _categorie == c,
                      onSelected: (_) => setState(() => _categorie = c),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            _champ(
              _titre,
              'Titre',
              _logement
                  ? 'Ex. : Studio meublé près de la fac'
                  : 'Ex. : Coupure d’eau demain',
              max: 120,
              validator: (v) =>
                  (v ?? '').trim().length < 3 ? 'Au moins 3 caractères.' : null,
            ),
            _champ(
              _description,
              'Description',
              'Écrivez votre annonce…',
              lignes: 5,
              max: 4000,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Ajoutez une description.' : null,
            ),
            if (_logement) ..._champsLogement(),
            const SizedBox(height: 8),
            Text('Photos (${_photos.length}/6)'),
            const SizedBox(height: 8),
            SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_photos.length < 6)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton.icon(
                        onPressed: _ajouterPhotos,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('Ajouter'),
                      ),
                    ),
                  ..._photos.map(
                    (photo) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _Photo(photo, largeur: 84, hauteur: 84),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _photos.remove(photo)),
                              child: const CircleAvatar(
                                radius: 11,
                                backgroundColor: Colors.black54,
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            CheckboxListTile(
              value: _commentaires,
              onChanged: (v) => setState(() => _commentaires = v ?? true),
              title: const Text('Autoriser les commentaires'),
              controlAffinity: ListTileControlAffinity.trailing,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              dense: true,
            ),
            const SizedBox(height: 10),
            _sectionProgrammation(),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _envoi ? null : _enregistrer,
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                minimumSize: const Size.fromHeight(52),
              ),
              child: _envoi
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _programmer
                          ? 'Programmer la publication'
                          : _init == null
                          ? 'Publier l’annonce'
                          : 'Enregistrer les modifications',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _sectionProgrammation() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: _programmer,
          onChanged: _basculerProgrammation,
          title: const Text('Programmer la publication'),
          subtitle: const Text(
            'L’annonce reste invisible jusqu’à la date choisie.',
          ),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        if (_programmer) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: _blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _datePublication == null
                        ? 'Aucune date choisie'
                        : 'Publication le ${formatDateHeure(_datePublication!)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: _changerDate,
                  child: const Text('Changer'),
                ),
              ],
            ),
          ),
          if (_erreurDate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text(
                _erreurDate!,
                style: const TextStyle(color: Color(0xFFC53030), fontSize: 12),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: HeureOfficielle(),
          ),
        ],
      ],
    ),
  );

  List<Widget> _champsLogement() {
    String? decimal(
      String? v, {
      required double min,
      required double max,
      required String label,
    }) {
      final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
      if (value == null) return '$label obligatoire.';
      if (value < min || value > max)
        return '$label : entre ${min.toStringAsFixed(0)} et ${max.toStringAsFixed(0)}.';
      return null;
    }

    String? entier(
      String? v, {
      required int min,
      required int max,
      required String label,
      bool optionnel = false,
    }) {
      final texte = (v ?? '').trim();
      if (texte.isEmpty) return optionnel ? null : '$label obligatoire.';
      final value = int.tryParse(texte);
      if (value == null || value < min || value > max)
        return '$label : entre $min et $max.';
      return null;
    }

    return [
      const Text(
        'Détails du logement',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _type,
        decoration: _deco('Type de logement'),
        items: Annonce.typesLogement
            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
            .toList(),
        onChanged: (v) => setState(() => _type = v),
        validator: (v) => v == null ? 'Choisissez un type.' : null,
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _champ(
              _loyer,
              'Loyer mensuel (DT)',
              '450',
              clavier: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) =>
                  decimal(v, min: 1, max: 100000, label: 'Le loyer'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _champ(
              _surface,
              'Surface (m²)',
              '22',
              clavier: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) =>
                  decimal(v, min: 1, max: 2000, label: 'La surface'),
            ),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: _champ(
              _chambres,
              'Chambres',
              '1',
              clavier: TextInputType.number,
              validator: (v) =>
                  entier(v, min: 0, max: 20, label: 'Le nombre de chambres'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _champ(
              _etage,
              'Étage (facultatif)',
              '2',
              clavier: const TextInputType.numberWithOptions(signed: true),
              validator: (v) => entier(
                v,
                min: -5,
                max: 200,
                label: 'L’étage',
                optionnel: true,
              ),
            ),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: _champ(
              _ville,
              'Ville',
              'Tunis',
              max: 80,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Ville obligatoire.' : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _champ(_quartier, 'Quartier', 'Centre', max: 80)),
        ],
      ),
      _champ(
        _adresse,
        'Adresse',
        '12 rue …',
        max: 200,
        validator: (v) =>
            (v ?? '').trim().length < 3 ? 'Adresse obligatoire.' : null,
      ),
    ];
  }

  Widget _champ(
    TextEditingController controller,
    String label,
    String hint, {
    int lignes = 1,
    int? max,
    TextInputType? clavier,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      maxLines: lignes,
      maxLength: max,
      keyboardType: clavier,
      validator: validator,
      decoration: _deco(
        label,
        hint: hint,
      ).copyWith(counterText: lignes > 1 ? null : ''),
    ),
  );

  InputDecoration _deco(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: _border),
    ),
  );
}

// ---------------------------------------------------------------------------
// Éléments partagés
// ---------------------------------------------------------------------------

/// Choix de la date puis de l'heure de publication (heure locale du téléphone).
Future<DateTime?> choisirDateHeurePublication(
  BuildContext context,
  DateTime? initiale,
) async {
  final maintenant = DateTime.now();
  final aujourdHui = DateTime(
    maintenant.year,
    maintenant.month,
    maintenant.day,
  );
  var depart = initiale?.toLocal() ?? maintenant.add(const Duration(hours: 1));
  if (depart.isBefore(maintenant))
    depart = maintenant.add(const Duration(hours: 1));
  final jour = await showDatePicker(
    context: context,
    initialDate: DateTime(depart.year, depart.month, depart.day),
    firstDate: aujourdHui,
    lastDate: aujourdHui.add(const Duration(days: 365)),
    helpText: 'Date de publication',
  );
  if (jour == null || !context.mounted) return null;
  final heure = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(depart),
    helpText: 'Heure de publication',
  );
  if (heure == null) return null;
  return DateTime(jour.year, jour.month, jour.day, heure.hour, heure.minute);
}

/// Null si [date] est strictement dans le futur selon l'heure officielle (ou,
/// à défaut, celle du téléphone) ; sinon le message d'erreur à afficher.
Future<String?> verifierDateFuture(HeureService service, DateTime date) async {
  final resultat = await service.obtenirHeure();
  if (date.isAfter(resultat.heure)) return null;
  final source = resultat.estLocale ? 'heure du téléphone' : 'heure officielle';
  return 'Cette date est déjà passée ($source : ${formatDateHeure(resultat.heure)}). '
      'Choisissez une date et une heure futures.';
}

/// « Heure officielle : … » obtenue par un Future et affichée avec FutureBuilder.
class HeureOfficielle extends StatefulWidget {
  const HeureOfficielle({super.key});
  @override
  State<HeureOfficielle> createState() => _HeureOfficielleState();
}

class _HeureOfficielleState extends State<HeureOfficielle> {
  late Future<HeureResultat> _heure;

  @override
  void initState() {
    super.initState();
    _heure = context.read<HeureService>().obtenirHeure();
  }

  void _actualiser() => setState(
    () => _heure = context.read<HeureService>().obtenirHeure(forcer: true),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<HeureResultat>(
    future: _heure,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Row(
          children: [
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Récupération de l’heure officielle…',
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ],
        );
      }
      if (snapshot.hasError) {
        return const Text(
          'Impossible d’obtenir l’heure pour le moment.',
          style: TextStyle(fontSize: 12, color: Color(0xFFC53030)),
        );
      }
      final resultat = snapshot.data!;
      final couleur = resultat.estLocale ? const Color(0xFFB7791F) : _muted;
      return Row(
        children: [
          Icon(
            resultat.estLocale ? Icons.phone_android : Icons.public,
            size: 16,
            color: couleur,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              resultat.estLocale
                  ? 'Heure du téléphone : ${formatDateHeure(resultat.heure)}\n${resultat.erreur}'
                  : 'Heure officielle : ${formatDateHeure(resultat.heure)}',
              style: TextStyle(fontSize: 12, color: couleur),
            ),
          ),
          IconButton(
            tooltip: 'Actualiser l’heure',
            visualDensity: VisualDensity.compact,
            onPressed: _actualiser,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ],
      );
    },
  );
}

String _note(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

String _quand(DateTime date) {
  final ecart = DateTime.now().difference(date);
  if (ecart.inMinutes < 1) return 'À l’instant';
  if (ecart.inHours < 1) return 'Il y a ${ecart.inMinutes} min';
  if (ecart.inDays < 1) return 'Il y a ${ecart.inHours} h';
  if (ecart.inDays == 1) return 'Hier';
  return formatJour(date);
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.annonce, required this.estMoi});
  final Annonce annonce;
  final bool estMoi;

  @override
  Widget build(BuildContext context) {
    final nom = annonce.proprietaireNom.isEmpty
        ? 'Utilisateur'
        : annonce.proprietaireNom;
    return Row(
      children: [
        _Avatar(nom),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                estMoi ? '$nom (vous)' : nom,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                annonce.dateAffichee == null
                    ? 'Publié'
                    : _quand(annonce.dateAffichee!),
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
        _Tag(annonce.categorie),
      ],
    );
  }
}

class _StatutBadge extends StatelessWidget {
  const _StatutBadge(this.annonce, {this.detaille = false});
  final Annonce annonce;
  final bool detaille;

  @override
  Widget build(BuildContext context) {
    final refusee =
        annonce.statut == StatutAnnonce.archivee &&
        annonce.motifModeration.isNotEmpty;
    final couleur = annonce.estProgrammee
        ? _blue
        : annonce.statut == StatutAnnonce.enAttente
        ? const Color(0xFFB7791F)
        : refusee
        ? const Color(0xFFC53030)
        : _muted;
    final libelle = refusee
        ? 'Refusée par la modération'
        : annonce.libelleProgrammation ?? annonce.statut.libelle;
    final texte = detaille
        ? switch (annonce.statut) {
            StatutAnnonce.programmee =>
              '$libelle : invisible pour les autres jusqu’à cette date.',
            StatutAnnonce.enAttente =>
              '$libelle : seuls vous et les administrateurs la voyez.',
            _ when refusee =>
              '$libelle : « ${annonce.motifModeration} ». Modifiez-la puis republiez-la.',
            _ =>
              '$libelle : elle n’est plus visible par les autres utilisateurs.',
          }
        : libelle;
    return _Bandeau(
      icon: switch (annonce.statut) {
        StatutAnnonce.programmee => Icons.schedule,
        StatutAnnonce.enAttente => Icons.hourglass_top,
        _ => Icons.archive_outlined,
      },
      couleur: couleur,
      texte: texte,
    );
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.icon,
    required this.couleur,
    required this.texte,
    this.action,
  });
  final IconData icon;
  final Color couleur;
  final String texte;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: couleur),
        const SizedBox(width: 6),
        Expanded(
          child: Text(texte, style: TextStyle(color: couleur, fontSize: 12)),
        ),
        ?action,
      ],
    ),
  );
}

class _ResumeLogement extends StatelessWidget {
  const _ResumeLogement(this.a);
  final Annonce a;

  @override
  Widget build(BuildContext context) => Text(
    [
      '${formatMontant(a.loyer)} / mois',
      a.typeLocation,
      '${a.surface.toStringAsFixed(0)} m²',
      if (a.ville.isNotEmpty) a.ville,
    ].join(' · '),
    style: const TextStyle(color: _blue, fontWeight: FontWeight.w600),
  );
}

class _DetailsLogement extends StatelessWidget {
  const _DetailsLogement(this.a);
  final Annonce a;

  @override
  Widget build(BuildContext context) {
    final lignes = <(IconData, String, String)>[
      (Icons.payments_outlined, 'Loyer', '${formatMontant(a.loyer)} / mois'),
      (Icons.home_work_outlined, 'Type', a.typeLocation),
      (Icons.square_foot, 'Surface', '${a.surface.toStringAsFixed(0)} m²'),
      (Icons.bed_outlined, 'Chambres', '${a.chambres}'),
      if (a.etage != null)
        (
          Icons.stairs_outlined,
          'Étage',
          a.etage == 0 ? 'Rez-de-chaussée' : '${a.etage}',
        ),
      (
        Icons.place_outlined,
        'Adresse',
        [a.adresse, a.quartier, a.ville].where((s) => s.isNotEmpty).join(', '),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: lignes
            .map(
              (l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(l.$1, size: 18, color: _blue),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: Text(l.$2, style: const TextStyle(color: _muted)),
                    ),
                    Expanded(
                      child: Text(
                        l.$3,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Etoiles extends StatelessWidget {
  const _Etoiles(this.note);
  final double note;

  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(5, (i) {
      final icon = note >= i + 1
          ? Icons.star
          : note >= i + .5
          ? Icons.star_half
          : Icons.star_border;
      return Icon(icon, size: 18, color: const Color(0xFFE5A400));
    }),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.nom);
  final String nom;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 19,
    backgroundColor: const Color(0xFF3A729B),
    child: Text(
      nom.isEmpty ? '?' : nom[0].toUpperCase(),
      style: const TextStyle(color: Colors.white),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFDCEBFC),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11, color: _ink)),
  );
}

class _Galerie extends StatelessWidget {
  const _Galerie(this.photos, {required this.hauteur});
  final List<String> photos;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return _PhotoVide(hauteur: hauteur);
    return SizedBox(
      height: hauteur,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _Photo(
            photos[index],
            largeur: hauteur * 1.35,
            hauteur: hauteur,
          ),
        ),
      ),
    );
  }
}

/// Photo serveur (`/photos/...`) ou fichier local pas encore envoyé.
class _Photo extends StatelessWidget {
  const _Photo(this.chemin, {required this.largeur, required this.hauteur});
  final String chemin;
  final double largeur;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    Widget erreur(BuildContext _, Object _, StackTrace? _) =>
        _PhotoVide(largeur: largeur, hauteur: hauteur, cassee: true);
    if (ApiClient.isRemotePhoto(chemin)) {
      return Image.network(
        ApiClient.photoUrl(chemin),
        width: largeur,
        height: hauteur,
        fit: BoxFit.cover,
        errorBuilder: erreur,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : SizedBox(
                width: largeur,
                height: hauteur,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
      );
    }
    return Image.file(
      File(chemin),
      width: largeur,
      height: hauteur,
      fit: BoxFit.cover,
      errorBuilder: erreur,
    );
  }
}

class _PhotoVide extends StatelessWidget {
  const _PhotoVide({
    this.largeur = double.infinity,
    required this.hauteur,
    this.cassee = false,
  });
  final double largeur;
  final double hauteur;
  final bool cassee;

  @override
  Widget build(BuildContext context) => Container(
    width: largeur,
    height: hauteur,
    decoration: BoxDecoration(
      color: const Color(0xFF9DBFE0),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          cassee ? Icons.broken_image_outlined : Icons.image_outlined,
          size: 18,
          color: _blue,
        ),
        if (!cassee) ...const [
          SizedBox(width: 7),
          Text('Aucune photo', style: TextStyle(fontSize: 12, color: _ink)),
        ],
      ],
    ),
  );
}
