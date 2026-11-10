import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/complaint_model.dart';
import '../../models/conversation_reclamation.dart';
import '../../providers/assistant_reclamation_provider.dart';
import '../../services/assistant_reclamation_service.dart';
import 'complaint_form_screen.dart';

const _ink = Color(0xFF14263F);
const _bleu = Color(0xFF0F3D75);
const _pale = Color(0xFFFBFCFE);
const _bord = Color(0xFFE4EAF2);
const _gris = Color(0xFF66748A);
const _ambre = Color(0xFFB7791F);

Color _couleurUrgence(String urgence) => switch (urgence) {
  'eleve' => const Color(0xFFC53030),
  'faible' => const Color(0xFF2F855A),
  _ => _ambre,
};

IconData _iconeCategorie(String categorie) => switch (categorie) {
  'plomberie' => Icons.water_drop_outlined,
  'electricite' => Icons.bolt_outlined,
  'chauffage_climatisation' => Icons.thermostat_outlined,
  'retard_loyer' => Icons.payments_outlined,
  'voisinage' => Icons.groups_outlined,
  'degradations' => Icons.handyman_outlined,
  'contrat' => Icons.description_outlined,
  'retard_reparations' => Icons.schedule,
  'caution' => Icons.savings_outlined,
  'photos_annonce' => Icons.image_search_outlined,
  'entretien' => Icons.cleaning_services_outlined,
  _ => Icons.help_outline,
};

String _date(DateTime? date) => date == null
    ? ''
    : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

/// Traduit l'analyse de l'IA vers les catégories du formulaire de réclamation.
ComplaintCategory categorieFormulaire(String categorie) => switch (categorie) {
  'plomberie' => ComplaintCategory.fuiteEau,
  'electricite' => ComplaintCategory.electricite,
  'chauffage_climatisation' => ComplaintCategory.chauffage,
  'degradations' || 'entretien' => ComplaintCategory.equipement,
  'contrat' || 'retard_reparations' => ComplaintCategory.proprietaire,
  _ => ComplaintCategory.autre,
};

/// Exemples proposés au début d'une conversation : (libellé, texte complet).
const _suggestionsLocataire = [
  ('Fuite d’eau', 'Il y a une fuite d’eau dans mon logement et le propriétaire ne répond pas.'),
  ('Caution non rendue', 'J’ai quitté le logement et ma caution ne m’a pas été rendue.'),
  ('Réparation en retard', 'J’ai signalé une panne il y a plusieurs semaines et rien n’a été réparé.'),
];
const _suggestionsProprietaire = [
  ('Loyer impayé', 'Mon locataire n’a pas payé son loyer ce mois-ci.'),
  ('Logement dégradé', 'J’ai constaté des dégradations dans le logement que je loue.'),
  ('Bruit signalé', 'Des voisins se plaignent du bruit causé par mon locataire.'),
];

class _Badge extends StatelessWidget {
  const _Badge(this.texte, {this.couleur = _bleu, this.icone});
  final String texte;
  final Color couleur;
  final IconData? icone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icone != null) ...[
          Icon(icone, size: 13, color: couleur),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            texte,
            style: TextStyle(fontSize: 11, color: couleur, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

/// Pastille ronde teintée autour d'une icône.
class _Pastille extends StatelessWidget {
  const _Pastille(this.icone, {this.taille = 42});
  final IconData icone;
  final double taille;

  @override
  Widget build(BuildContext context) => Container(
    width: taille,
    height: taille,
    decoration: BoxDecoration(color: _bleu.withValues(alpha: .12), shape: BoxShape.circle),
    child: Icon(icone, size: taille * .52, color: _bleu),
  );
}

/// Historique des conversations avec l'assistant.
class AssistantReclamationsScreen extends StatelessWidget {
  const AssistantReclamationsScreen({super.key, this.service});
  final AssistantReclamationService? service;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AssistantReclamationProvider(service: service)..charger(),
    child: const _Historique(),
  );
}

class _Historique extends StatelessWidget {
  const _Historique();

  void _ouvrir(BuildContext context, ConversationReclamation? conversation) {
    final provider = context.read<AssistantReclamationProvider>();
    if (conversation == null) {
      provider.nouvelle();
    } else {
      provider.ouvrir(conversation);
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: provider,
          child: const ConversationReclamationScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssistantReclamationProvider>();
    final Widget corps;
    if (provider.chargement && provider.conversations.isEmpty) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (!provider.roleAccepte) {
      corps = const _Message(
        icone: Icons.lock_outline,
        texte: 'Cet assistant est réservé aux locataires et aux propriétaires.',
      );
    } else if (provider.conversations.isEmpty) {
      corps = _Message(
        icone: Icons.forum_outlined,
        titre: provider.erreur == null ? 'Aucune conversation' : null,
        texte: provider.erreur ??
            'Décrivez votre problème de location : l’assistant l’analyse et vous propose une solution adaptée.',
      );
    } else {
      corps = RefreshIndicator(
        onRefresh: provider.charger,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: provider.conversations.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final conversation = provider.conversations[index];
            return _CarteConversation(
              conversation: conversation,
              onTap: () => _ouvrir(context, conversation),
            );
          },
        ),
      );
    }
    return Scaffold(
      backgroundColor: _pale,
      appBar: AppBar(
        backgroundColor: _pale,
        title: const Text('Assistant réclamations'),
      ),
      floatingActionButton: provider.roleAccepte
          ? FloatingActionButton.extended(
              onPressed: () => _ouvrir(context, null),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Nouvelle réclamation'),
            )
          : null,
      body: corps,
    );
  }
}

class _CarteConversation extends StatelessWidget {
  const _CarteConversation({required this.conversation, required this.onTap});
  final ConversationReclamation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final urgence = _couleurUrgence(conversation.urgence);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(color: urgence, child: const SizedBox(width: 5)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Pastille(_iconeCategorie(conversation.categorie)),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conversation.titre,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, height: 1.25),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${categoriesAssistant[conversation.categorie] ?? conversation.categorie} · ${_date(conversation.miseAJour)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: _gris),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _Badge(urgencesAssistant[conversation.urgence] ?? conversation.urgence, couleur: urgence),
                                _Badge(statutsAssistant[conversation.statut] ?? conversation.statut, couleur: _gris),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icone, required this.texte, this.titre, this.enfants = const []});
  final IconData icone;
  final String? titre;
  final String texte;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pastille(icone, taille: 84),
          const SizedBox(height: 16),
          if (titre != null) ...[
            Text(
              titre!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
          ],
          Text(texte, textAlign: TextAlign.center, style: const TextStyle(color: _gris, height: 1.35)),
          ...enfants,
        ],
      ),
    ),
  );
}

/// Discussion : l'historique, l'analyse de chaque message et la zone de saisie.
/// Chatbot ouvert depuis une photo refusée : la réclamation lui est envoyée aussitôt.
class ReclamationPhotoScreen extends StatelessWidget {
  const ReclamationPhotoScreen({super.key, required this.message, this.service});
  final String message;
  final AssistantReclamationService? service;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AssistantReclamationProvider(service: service)..nouvelle(),
    child: ConversationReclamationScreen(texteInitial: message, envoyerDirectement: true),
  );
}

class ConversationReclamationScreen extends StatefulWidget {
  const ConversationReclamationScreen({super.key, this.texteInitial = '', this.envoyerDirectement = false});
  final String texteInitial;
  final bool envoyerDirectement;

  @override
  State<ConversationReclamationScreen> createState() => _ConversationReclamationScreenState();
}

class _ConversationReclamationScreenState extends State<ConversationReclamationScreen> {
  late final _saisie = TextEditingController(text: widget.texteInitial);
  final _defilement = ScrollController();

  @override
  void initState() {
    super.initState();
    if (!widget.envoyerDirectement) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<AssistantReclamationProvider>();
      await provider.charger();
      if (mounted) await _envoyer(provider);
    });
  }

  @override
  void dispose() {
    _saisie.dispose();
    _defilement.dispose();
    super.dispose();
  }

  void _allerEnBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_defilement.hasClients) {
        _defilement.jumpTo(_defilement.position.maxScrollExtent);
      }
    });
  }

  Future<void> _envoyer(AssistantReclamationProvider provider) async {
    final texte = _saisie.text.trim();
    if (texte.isEmpty || provider.envoiEnCours) return;
    _saisie.clear();
    _allerEnBas();
    final envoye = await provider.envoyer(texte);
    if (!mounted) return;
    if (!envoye) {
      _saisie.text = texte;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(provider.erreur ?? 'Envoi impossible.')));
    }
    _allerEnBas();
  }

  Future<void> _supprimer(AssistantReclamationProvider provider, String id) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogue) => AlertDialog(
        title: const Text('Supprimer cette conversation ?'),
        content: const Text('Les messages et l’analyse seront effacés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogue, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogue, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    final navigateur = Navigator.of(context);
    if (await provider.supprimer(id)) navigateur.pop();
  }

  void _creerReclamation(ConversationReclamation conversation) {
    final description = conversation.messages
        .where((m) => m.deUtilisateur)
        .map((m) => m.texte)
        .join('\n');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComplaintFormScreen(
          sujetInitial: conversation.titre,
          descriptionInitiale: description,
          categorieInitiale: categorieFormulaire(conversation.categorie),
          prioriteInitiale: switch (conversation.urgence) {
            'eleve' => ComplaintPriority.urgente,
            'faible' => ComplaintPriority.faible,
            _ => ComplaintPriority.moyenne,
          },
        ),
      ),
    );
  }

  Widget _accueil(String role) {
    final proprietaire = role == 'proprietaire';
    return _Message(
      icone: Icons.support_agent,
      titre: 'Comment puis-je vous aider ?',
      texte: proprietaire
          ? 'Décrivez le problème avec votre logement ou votre locataire, en français ou en arabe.'
          : 'Décrivez le problème dans votre logement, en français ou en arabe.',
      enfants: [
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (libelle, texte) in proprietaire ? _suggestionsProprietaire : _suggestionsLocataire)
              ActionChip(
                label: Text(libelle),
                onPressed: () => _saisie.text = texte,
              ),
          ],
        ),
      ],
    );
  }

  Widget _enTete(String role, ConversationReclamation? conversation) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
    child: Row(
      children: [
        _Badge(
          nomRoleAssistant(role),
          couleur: _ink,
          icone: role == 'proprietaire' ? Icons.apartment_outlined : Icons.person_outline,
        ),
        if (conversation != null) ...[
          const SizedBox(width: 6),
          _Badge(
            categoriesAssistant[conversation.categorie] ?? conversation.categorie,
            icone: _iconeCategorie(conversation.categorie),
          ),
          const SizedBox(width: 6),
          _Badge(
            urgencesAssistant[conversation.urgence] ?? conversation.urgence,
            couleur: _couleurUrgence(conversation.urgence),
            icone: Icons.priority_high,
          ),
          const SizedBox(width: 6),
          _Badge(statutsAssistant[conversation.statut] ?? conversation.statut, couleur: _gris),
        ],
      ],
    ),
  );

  Widget _zoneSaisie(AssistantReclamationProvider provider) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: _bord)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _saisie,
                builder: (_, valeur, _) => TextField(
                  controller: _saisie,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  textDirection: estTexteArabe(valeur.text) ? TextDirection.rtl : TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: 'Décrivez votre réclamation…',
                    counterText: '',
                    filled: true,
                    fillColor: _pale,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: _bleu),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Envoyer',
              onPressed: provider.envoiEnCours ? null : () => _envoyer(provider),
              icon: const Icon(Icons.arrow_upward),
              style: IconButton.styleFrom(backgroundColor: _bleu, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssistantReclamationProvider>();
    final conversation = provider.courante;
    final messages = conversation?.messages ?? const <MessageAssistant>[];
    final enCours = provider.messageEnCours;
    final role = conversation?.role ?? provider.role;
    return Scaffold(
      backgroundColor: _pale,
      appBar: AppBar(
        backgroundColor: _pale,
        title: Text(
          conversation?.titre ?? 'Nouvelle réclamation',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (conversation != null)
            PopupMenuButton<String>(
              tooltip: 'Options',
              onSelected: (valeur) => valeur == 'supprimer'
                  ? _supprimer(provider, conversation.id)
                  : provider.changerStatut(valeur),
              itemBuilder: (_) => [
                for (final entree in statutsAssistant.entries)
                  CheckedPopupMenuItem(
                    value: entree.key,
                    checked: conversation.statut == entree.key,
                    child: Text(entree.value),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          _enTete(role, conversation),
          Expanded(
            child: messages.isEmpty && enCours == null
                ? _accueil(role)
                : ListView(
                    controller: _defilement,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    children: [
                      for (final message in messages)
                        message.deUtilisateur ? _BulleUtilisateur(message.texte) : _BulleAssistant(message),
                      if (enCours != null) ...[
                        _BulleUtilisateur(enCours),
                        const _Reflexion(),
                      ],
                      if (conversation != null && enCours == null)
                        Padding(
                          padding: const EdgeInsets.only(left: 38, top: 2),
                          child: OutlinedButton.icon(
                            onPressed: () => _creerReclamation(conversation),
                            icon: const Icon(Icons.assignment_add, size: 18),
                            label: const Text('Créer la réclamation officielle'),
                          ),
                        ),
                    ],
                  ),
          ),
          _zoneSaisie(provider),
        ],
      ),
    );
  }
}

/// Texte affiché de droite à gauche s'il est écrit en arabe.
class _TexteAdapte extends StatelessWidget {
  const _TexteAdapte(this.texte, {this.style});
  final String texte;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    style: style,
    textDirection: estTexteArabe(texte) ? TextDirection.rtl : TextDirection.ltr,
  );
}

class _BulleUtilisateur extends StatelessWidget {
  const _BulleUtilisateur(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .8),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: _bleu,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(5),
        ),
      ),
      child: _TexteAdapte(texte, style: const TextStyle(color: Colors.white, height: 1.35)),
    ),
  );
}

/// Avatar de l'assistant suivi de son contenu.
class _LigneAssistant extends StatelessWidget {
  const _LigneAssistant({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Pastille(Icons.support_agent, taille: 30),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    ),
  );
}

const _formeAssistant = BorderRadius.only(
  topLeft: Radius.circular(5),
  topRight: Radius.circular(18),
  bottomLeft: Radius.circular(18),
  bottomRight: Radius.circular(18),
);

class _Reflexion extends StatelessWidget {
  const _Reflexion();

  @override
  Widget build(BuildContext context) => const _LigneAssistant(
    child: Padding(
      padding: EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Analyse de votre réclamation…', style: TextStyle(color: _gris)),
        ],
      ),
    ),
  );
}

class _BulleAssistant extends StatelessWidget {
  const _BulleAssistant(this.message);
  final MessageAssistant message;

  /// Encadré teinté dans la bulle (questions, avis d'un professionnel).
  Widget _encadre(Color couleur, IconData icone, String titre, List<String> lignes) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 17, color: couleur),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TexteAdapte(titre, style: TextStyle(color: couleur, fontWeight: FontWeight.w700, fontSize: 13)),
              for (final ligne in lignes)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _TexteAdapte(ligne, style: const TextStyle(color: _ink, height: 1.3)),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _details(BuildContext context, AnalyseReclamation analyse, bool arabe) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      visualDensity: VisualDensity.compact,
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      iconColor: _gris,
      collapsedIconColor: _gris,
      title: _TexteAdapte(
        arabe ? 'تفاصيل التحليل' : 'Détails de l’analyse',
        style: const TextStyle(color: _gris, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      children: [
        Text(
          'Concerne : ${personnesAssistant[analyse.personneConcernee] ?? analyse.personneConcernee}',
          style: const TextStyle(color: _gris, fontSize: 12),
        ),
        for (final info in analyse.informations)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: _TexteAdapte('${info.champ} : ${info.valeur}', style: const TextStyle(color: _gris, fontSize: 12)),
          ),
        if (message.sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Sources : ${message.sources.join(' · ')}', style: const TextStyle(color: _gris, fontSize: 11)),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final analyse = message.analyse;
    final arabe = estTexteArabe(message.texte);
    return _LigneAssistant(
      // Material plutôt qu'un fond décoré : le volet « Détails » y dessine son effet de toucher.
      child: Material(
        color: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: _formeAssistant,
          side: BorderSide(color: _bord),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TexteAdapte(message.texte, style: const TextStyle(color: _ink, height: 1.4)),
              if (analyse != null && analyse.questions.isNotEmpty)
                _encadre(
                  _bleu,
                  Icons.help_outline,
                  arabe ? 'لمساعدتك أكثر' : 'Pour vous aider davantage',
                  analyse.questions,
                ),
              if (analyse != null && analyse.avisProfessionnel)
                _encadre(
                  _ambre,
                  Icons.gavel,
                  arabe ? 'قد تتطلب هذه الحالة رأي مختص.' : 'Cette situation peut nécessiter l’avis d’un professionnel.',
                  const [],
                ),
              if (analyse != null) _details(context, analyse, arabe) else const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
