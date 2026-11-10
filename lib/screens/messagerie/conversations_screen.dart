import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/messagerie.dart';
import '../../providers/auth_provider.dart';
import '../../providers/messagerie_provider.dart';
import '../../providers/user_provider.dart';
import '../../core/constants/langues.dart';
import '../../services/api_client.dart';
import '../../services/messagerie_service.dart';
import 'discussion_screen.dart';

String formatDateMessage(DateTime date) {
  final maintenant = DateTime.now();
  String deux(int n) => n.toString().padLeft(2, '0');
  final memeJour = date.year == maintenant.year && date.month == maintenant.month && date.day == maintenant.day;
  return memeJour ? '${deux(date.hour)}:${deux(date.minute)}' : '${deux(date.day)}/${deux(date.month)}';
}

/// Ouvre la discussion sur une annonce (créée au besoin). [locataireId] n'est
/// fourni que lorsque le propriétaire écrit le premier.
Future<void> contacterSurAnnonce(BuildContext context, {required String annonceId, String? locataireId, MessagerieService? service}) async {
  final messager = ScaffoldMessenger.of(context);
  final navigateur = Navigator.of(context);
  final userId = context.read<AuthProvider>().currentUserId;
  if (userId == null) return;
  final langue = context.read<UserProvider>().user?.langue ?? langueParDefaut;
  final messagerie = service ?? MessagerieService();
  try {
    final conversation = await messagerie.ouvrir(annonceId: annonceId, locataireId: locataireId);
    await navigateur.push(
      MaterialPageRoute<void>(
        builder: (_) => DiscussionScreen(conversation: conversation, userId: userId, langue: langue, service: messagerie),
      ),
    );
  } on ApiException catch (erreur) {
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(erreur.horsConnexion ? 'Connexion nécessaire pour démarrer une conversation.' : erreur.message)));
  }
}

/// Icône de l'en-tête de l'Accueil, avec le nombre de messages non lus.
class IconeMessages extends StatefulWidget {
  const IconeMessages({super.key, required this.couleur});
  final Color couleur;

  @override
  State<IconeMessages> createState() => _IconeMessagesState();
}

class _IconeMessagesState extends State<IconeMessages> {
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _actualiser();
      _minuteur = Timer.periodic(const Duration(seconds: 30), (_) => _actualiser());
    });
  }

  void _actualiser() {
    final userId = context.read<AuthProvider>().currentUserId;
    if (userId != null) context.read<MessagerieProvider>().actualiser(userId);
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nonLus = context.watch<MessagerieProvider>().nonLus;
    return IconButton(
      tooltip: 'Messages',
      icon: Badge(
        isLabelVisible: nonLus > 0,
        label: Text(nonLus > 9 ? '9+' : '$nonLus'),
        child: Icon(Icons.chat_bubble_outline, color: widget.couleur),
      ),
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ConversationsScreen()));
        if (mounted) _actualiser();
      },
    );
  }
}

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  String get _userId => context.read<AuthProvider>().currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MessagerieProvider>().actualiser(_userId);
    });
  }

  Future<void> _ouvrir(ConversationResume conversation) async {
    final provider = context.read<MessagerieProvider>();
    final userId = _userId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscussionScreen(
          conversation: conversation,
          userId: userId,
          langue: context.read<UserProvider>().user?.langue ?? langueParDefaut,
          service: MessagerieService(),
        ),
      ),
    );
    await provider.actualiser(userId);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MessagerieProvider>();
    final conversations = provider.conversations;
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: RefreshIndicator(
        onRefresh: () => provider.actualiser(_userId),
        child: conversations.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * .22),
                  if (provider.chargement)
                    const Center(child: CircularProgressIndicator())
                  else
                    _Vide(erreur: provider.erreur),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: conversations.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
                itemBuilder: (_, index) => _LigneConversation(
                  conversation: conversations[index],
                  lecteurId: _userId,
                  onTap: () => _ouvrir(conversations[index]),
                ),
              ),
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide({this.erreur});
  final String? erreur;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Column(
      children: [
        const Icon(Icons.forum_outlined, size: 54, color: AppCouleurs.bleuClair),
        const SizedBox(height: 12),
        Text(
          erreur ?? 'Aucune conversation pour le moment',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ouvrez un logement puis appuyez sur « Message » pour écrire au propriétaire.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppCouleurs.gris),
        ),
      ],
    ),
  );
}

class _LigneConversation extends StatelessWidget {
  const _LigneConversation({required this.conversation, required this.lecteurId, required this.onTap});
  final ConversationResume conversation;
  final String lecteurId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nonLu = conversation.nonLus > 0;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _Vignette(conversation),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.interlocuteurNom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatDateMessage(conversation.date),
            style: TextStyle(fontSize: 12, color: nonLu ? AppCouleurs.bleu : AppCouleurs.gris),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conversation.annonceTitre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppCouleurs.gris),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  conversation.apercu(lecteurId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: nonLu ? AppCouleurs.encre : AppCouleurs.gris,
                    fontWeight: nonLu ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (nonLu) Badge(label: Text('${conversation.nonLus}'), backgroundColor: AppCouleurs.bleu),
            ],
          ),
        ],
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette(this.conversation);
  final ConversationResume conversation;

  @override
  Widget build(BuildContext context) {
    final photo = conversation.annoncePhoto;
    final remplacement = Container(
      width: 52,
      height: 52,
      color: AppCouleurs.bleuPale,
      alignment: Alignment.center,
      child: const Icon(Icons.home_outlined, color: AppCouleurs.bleu),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: photo == null || !ApiClient.isRemotePhoto(photo)
          ? remplacement
          : CachedNetworkImage(
              imageUrl: ApiClient.photoUrl(photo),
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              placeholder: (_, _) => remplacement,
              errorWidget: (_, _, _) => remplacement,
            ),
    );
  }
}
