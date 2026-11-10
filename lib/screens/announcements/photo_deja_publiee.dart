import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/annonce.dart';
import '../../services/api_client.dart';
import '../complaints/assistant_reclamation_screen.dart';

const _rouge = Color(0xFFC53030);
const _largeur = 104.0;

/// Réclamation envoyée au chatbot quand l'utilisateur affirme que c'est sa maison.
String messageReclamationPhoto(String? titreAnnonce) =>
    'Je veux publier mon annonce mais ma photo est refusée car elle est déjà utilisée'
    '${titreAnnonce == null ? ' dans une autre annonce' : ' dans l’annonce « $titreAnnonce »'}. '
    'Je suis sûr(e) que c’est bien mon logement.';

class _Vignette extends StatelessWidget {
  const _Vignette({required this.legende, this.chemin});
  final String legende;
  final String? chemin;

  @override
  Widget build(BuildContext context) {
    final remplacement = Container(
      width: _largeur,
      height: 110,
      color: AppCouleurs.bleuPale,
      alignment: Alignment.center,
      child: const Icon(Icons.hide_image_outlined, color: AppCouleurs.gris),
    );
    final image = chemin;
    return SizedBox(
      width: _largeur,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: image == null
                ? remplacement
                : ApiClient.isRemotePhoto(image)
                ? CachedNetworkImage(
                    imageUrl: ApiClient.photoUrl(image),
                    width: _largeur,
                    height: 110,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => remplacement,
                    errorWidget: (_, _, _) => remplacement,
                  )
                : Image.file(
                    File(image),
                    width: _largeur,
                    height: 110,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => remplacement,
                  ),
          ),
          const SizedBox(height: 4),
          Text(legende, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppCouleurs.gris)),
        ],
      ),
    );
  }
}

/// Refus d'une photo déjà publiée. « C'est ma maison » envoie la réclamation au
/// chatbot ; sinon l'utilisateur revient au formulaire pour changer de photo.
Future<void> afficherAlertePhoto(BuildContext context, {String? photoLocale, CorrespondancePhoto? correspondance}) async {
  final navigateur = Navigator.of(context);
  final reclamer = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogue) => AlertDialog(
      icon: const Icon(Icons.gpp_maybe_outlined, color: _rouge, size: 34),
      title: const Text('Photo déjà publiée'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Votre annonce ne peut pas être publiée avec cette photo : changez-la.'),
            if (photoLocale != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Vignette(chemin: photoLocale, legende: 'Votre photo'),
                  const SizedBox(width: 8),
                  _Vignette(chemin: correspondance?.photoCible, legende: 'Déjà publiée'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text('Si vous êtes sûr(e) que c’est votre maison, envoyez une réclamation à notre chatbot.'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogue, true), child: const Text('C’est ma maison')),
        FilledButton(onPressed: () => Navigator.pop(dialogue, false), child: const Text('Changer la photo')),
      ],
    ),
  );
  if (reclamer != true) return;
  await navigateur.push(
    MaterialPageRoute<void>(
      builder: (_) => ReclamationPhotoScreen(message: messageReclamationPhoto(correspondance?.annonceCibleTitre)),
    ),
  );
}
