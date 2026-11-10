import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants/langues.dart';
import '../../core/theme/app_theme.dart';
import '../../models/messagerie.dart';
import '../../providers/messagerie_provider.dart';
import '../../providers/traduction_provider.dart';
import '../../services/api_client.dart';
import '../../services/messagerie_service.dart';
import '../../services/traduction_service.dart';
import 'conversations_screen.dart';

const _maxPhotos = 4;

class DiscussionScreen extends StatefulWidget {
  const DiscussionScreen({
    super.key,
    required this.conversation,
    required this.userId,
    required this.langue,
    required this.service,
    this.traduction,
    this.periode = const Duration(seconds: 5),
  });

  final ConversationResume conversation;
  final String userId;
  final String langue;
  final MessagerieService service;
  final TraductionService? traduction;
  final Duration periode;

  @override
  State<DiscussionScreen> createState() => _DiscussionScreenState();
}

class _DiscussionScreenState extends State<DiscussionScreen> {
  late final DiscussionProvider _provider;
  final _saisie = TextEditingController();
  final _picker = ImagePicker();
  List<String> _photos = const [];
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _provider = DiscussionProvider(
      conversationId: widget.conversation.id,
      userId: widget.userId,
      langueCible: widget.langue,
      service: widget.service,
      traduction: widget.traduction,
      periode: widget.periode,
    )..demarrer();
    _saisie.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _provider.dispose();
    _saisie.dispose();
    super.dispose();
  }

  bool get _peutEnvoyer => !_envoi && (_saisie.text.trim().isNotEmpty || _photos.isNotEmpty);

  Future<void> _envoyer() async {
    if (!_peutEnvoyer) return;
    final texte = _saisie.text.trim();
    final photos = _photos;
    setState(() => _envoi = true);
    try {
      await _provider.envoyer(texte, photos, langueProfil: widget.langue);
      if (!mounted) return;
      _saisie.clear();
      setState(() => _photos = const []);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Impossible de préparer ce message. Réessayez.')));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _ajouterPhotos() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final List<XFile> choisies;
    if (source == ImageSource.camera) {
      final photo = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1920);
      choisies = [?photo];
    } else {
      choisies = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
    }
    if (!mounted || choisies.isEmpty) return;
    final toutes = [..._photos, ...choisies.map((photo) => photo.path)];
    if (toutes.length > _maxPhotos) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('$_maxPhotos photos maximum par message.')));
    }
    setState(() => _photos = toutes.take(_maxPhotos).toList());
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _provider,
    child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.conversation.interlocuteurNom, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              widget.conversation.annonceTitre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppCouleurs.gris),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const _BandeauHorsLigne(),
          Expanded(child: _Fil(userId: widget.userId)),
          _zoneSaisie(),
        ],
      ),
    ),
  );

  Widget _zoneSaisie() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_photos.isNotEmpty)
            SizedBox(
              height: 78,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                children: [
                  for (final (index, photo) in _photos.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(File(photo), width: 70, height: 70, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () => setState(
                                () => _photos = [..._photos.take(index), ..._photos.skip(index + 1)],
                              ),
                              child: const CircleAvatar(
                                radius: 11,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Ajouter des photos',
                onPressed: _envoi || _photos.length >= _maxPhotos ? null : _ajouterPhotos,
                icon: const Icon(Icons.add_photo_alternate_outlined, color: AppCouleurs.bleu),
              ),
              Expanded(
                child: TextField(
                  controller: _saisie,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Votre message…',
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Envoyer',
                onPressed: _peutEnvoyer ? _envoyer : null,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _BandeauHorsLigne extends StatelessWidget {
  const _BandeauHorsLigne();

  @override
  Widget build(BuildContext context) {
    if (!context.watch<DiscussionProvider>().horsLigne) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF5E5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: const Text(
        'Hors connexion : vos messages partiront au retour du réseau.',
        style: TextStyle(fontSize: 12, color: Color(0xFFA76A0A), fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Fil extends StatelessWidget {
  const _Fil({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DiscussionProvider>();
    if (provider.chargement) return const Center(child: CircularProgressIndicator());
    final messages = provider.messages;
    if (messages.isEmpty) {
      final erreur = provider.erreur;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                erreur ?? 'Écrivez votre premier message.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppCouleurs.gris),
              ),
              if (erreur != null) TextButton(onPressed: provider.actualiser, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }
    // Liste inversée : le dernier message reste en bas, au-dessus de la saisie.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      itemCount: messages.length,
      itemBuilder: (_, index) {
        final message = messages[messages.length - 1 - index];
        return _Bulle(key: ValueKey(message.clientId ?? message.id), message: message, estMoi: message.auteurId == userId);
      },
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({super.key, required this.message, required this.estMoi});
  final MessageDiscussion message;
  final bool estMoi;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DiscussionProvider>();
    final traduction = provider.traduction(message.id);
    final afficheTraduction = traduction.etat == EtatTraduction.traduit && traduction.afficherTraduction;
    final couleurTexte = estMoi ? Colors.white : AppCouleurs.encre;
    final couleurDiscrete = estMoi ? const Color(0xFFDCE8F6) : AppCouleurs.gris;
    final texte = afficheTraduction ? traduction.texte! : message.texte;
    return Align(
      alignment: estMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: message.etat == EtatEnvoi.echec
                ? const Color(0xFFC53030)
                : estMoi
                ? AppCouleurs.bleu
                : AppCouleurs.bleuPale,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(estMoi ? 16 : 4),
              bottomRight: Radius.circular(estMoi ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.photos.isNotEmpty) ...[
                _GrillePhotos(message.photos),
                if (message.texte.isNotEmpty) const SizedBox(height: 7),
              ],
              if (message.texte.isNotEmpty) Text(texte, style: TextStyle(color: couleurTexte, height: 1.3)),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatDateMessage(message.date), style: TextStyle(fontSize: 11, color: couleurDiscrete)),
                  if (message.etat == EtatEnvoi.enAttente) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.schedule, size: 12, color: couleurDiscrete, semanticLabel: 'En attente d’envoi'),
                  ],
                ],
              ),
              if (message.etat == EtatEnvoi.echec) _Echec(message),
              if (provider.peutTraduire(message)) _LigneTraduction(message, traduction, afficheTraduction),
            ],
          ),
        ),
      ),
    );
  }
}

class _Echec extends StatelessWidget {
  const _Echec(this.message);
  final MessageDiscussion message;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DiscussionProvider>();
    final style = TextButton.styleFrom(foregroundColor: Colors.white, visualDensity: VisualDensity.compact);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message.erreur ?? 'Message non envoyé.',
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Wrap(
          children: [
            TextButton(style: style, onPressed: () => provider.reessayer(message.id), child: const Text('Réessayer')),
            TextButton(style: style, onPressed: () => provider.abandonner(message.id), child: const Text('Supprimer')),
          ],
        ),
      ],
    );
  }
}

class _LigneTraduction extends StatelessWidget {
  const _LigneTraduction(this.message, this.traduction, this.afficheTraduction);
  final MessageDiscussion message;
  final TraductionMessage traduction;
  final bool afficheTraduction;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DiscussionProvider>();
    final style = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
    return switch (traduction.etat) {
      EtatTraduction.idle => TextButton.icon(
        style: style,
        onPressed: () => provider.traduire(message),
        icon: const Icon(Icons.translate, size: 15),
        label: Text('Traduire en ${nomLangue(provider.langueCible)}'),
      ),
      EtatTraduction.loading => const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Traduction en cours…', style: TextStyle(fontSize: 12, color: AppCouleurs.gris)),
      ),
      EtatTraduction.erreur => TextButton(
        style: style,
        onPressed: () => provider.traduire(message),
        child: const Text('Traduction indisponible · Réessayer'),
      ),
      EtatTraduction.traduit => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (afficheTraduction)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Traduction automatique, le texte original fait foi',
                style: TextStyle(fontSize: 11, color: AppCouleurs.gris),
              ),
            ),
          TextButton(
            style: style,
            onPressed: () => provider.basculerTraduction(message.id),
            child: Text(afficheTraduction ? 'Voir l’original (${nomLangue(message.langue)})' : 'Voir la traduction'),
          ),
        ],
      ),
    };
  }
}

class _GrillePhotos extends StatelessWidget {
  const _GrillePhotos(this.photos);
  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    final cote = photos.length == 1 ? 220.0 : 108.0;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final photo in photos)
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => _PhotoPleinEcran(photo)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _ImageMessage(photo, largeur: cote, hauteur: cote),
            ),
          ),
      ],
    );
  }
}

class _ImageMessage extends StatelessWidget {
  const _ImageMessage(this.chemin, {this.largeur, this.hauteur, this.ajustement = BoxFit.cover});
  final String chemin;
  final double? largeur;
  final double? hauteur;
  final BoxFit ajustement;

  @override
  Widget build(BuildContext context) {
    final remplacement = Container(
      width: largeur,
      height: hauteur,
      color: AppCouleurs.bordure,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: AppCouleurs.gris),
    );
    if (ApiClient.isRemotePhoto(chemin)) {
      return CachedNetworkImage(
        imageUrl: ApiClient.photoUrl(chemin),
        width: largeur,
        height: hauteur,
        fit: ajustement,
        placeholder: (_, _) => remplacement,
        errorWidget: (_, _, _) => remplacement,
      );
    }
    return Image.file(
      File(chemin),
      width: largeur,
      height: hauteur,
      fit: ajustement,
      errorBuilder: (_, _, _) => remplacement,
    );
  }
}

class _PhotoPleinEcran extends StatelessWidget {
  const _PhotoPleinEcran(this.chemin);
  final String chemin;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
    body: Center(
      child: InteractiveViewer(child: _ImageMessage(chemin, ajustement: BoxFit.contain)),
    ),
  );
}
