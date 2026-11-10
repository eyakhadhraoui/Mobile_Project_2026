import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/validators.dart';
import '../providers/mot_de_passe_provider.dart';
import '../services/mot_de_passe_service.dart';

const _rouge = Color(0xFFC53030);
const _orange = Color(0xFFB7791F);
const _vert = Color(0xFF16804A);
const _gris = Color(0xFF66748A);

/// À placer sous le champ « mot de passe » : force (barre colorée) et résultat
/// de la vérification des fuites, lus dans le [MotDePasseProvider] de l'écran.
class IndicateurMotDePasse extends StatelessWidget {
  const IndicateurMotDePasse({super.key});

  @override
  Widget build(BuildContext context) {
    final verification = context.watch<MotDePasseProvider>();
    final force = verification.force;
    if (force == null) return const SizedBox.shrink();
    final (couleur, progression, conseil) = switch (force) {
      ForceMotDePasse.faible => (_rouge, 1 / 3, 'Ajoutez des majuscules, chiffres ou symboles.'),
      ForceMotDePasse.moyen => (_orange, 2 / 3, 'Plus long (12 caractères) ou plus varié, il serait plus sûr.'),
      ForceMotDePasse.fort => (_vert, 1.0, 'Bon mot de passe.'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progression,
              minHeight: 5,
              color: couleur,
              backgroundColor: couleur.withValues(alpha: .15),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Force : ${force.libelle.toLowerCase()} · $conseil',
            style: TextStyle(fontSize: 12, color: couleur),
          ),
          _EtatFuites(verification),
        ],
      ),
    );
  }
}

class _EtatFuites extends StatelessWidget {
  const _EtatFuites(this.verification);
  final MotDePasseProvider verification;

  @override
  Widget build(BuildContext context) {
    final (Widget? icone, String? texte, Color couleur) = switch (verification.etat) {
      EtatVerificationMotDePasse.idle => (null, null, _gris),
      EtatVerificationMotDePasse.loading => (
        const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2)),
        'Vérification...',
        _gris,
      ),
      EtatVerificationMotDePasse.compromis => (
        const Icon(Icons.gpp_bad_outlined, size: 16, color: _rouge),
        messageCompromis(verification.nombreFuites),
        _rouge,
      ),
      EtatVerificationMotDePasse.sur => (
        const Icon(Icons.verified_user_outlined, size: 16, color: _vert),
        'Aucune fuite connue',
        _vert,
      ),
      EtatVerificationMotDePasse.indisponible => (
        const Icon(Icons.cloud_off_outlined, size: 14, color: _gris),
        'Vérification des fuites indisponible',
        _gris,
      ),
    };
    if (texte == null) return const SizedBox.shrink();
    final discret = verification.etat == EtatVerificationMotDePasse.indisponible;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?icone,
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texte,
              style: TextStyle(
                fontSize: discret ? 11 : 12,
                color: couleur,
                fontWeight: verification.etat == EtatVerificationMotDePasse.compromis ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// « Ce mot de passe apparaît dans des fuites de données (X fois). Choisissez-en un autre. »
String messageCompromis(int nombre) =>
    'Ce mot de passe apparaît dans des fuites de données (${formatNombre(nombre)} fois). Choisissez-en un autre.';

/// 9659365 → « 9 659 365 ».
String formatNombre(int nombre) =>
    nombre.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

/// Vérification au moment de la validation du formulaire.
/// Retourne true si le mot de passe peut être utilisé :
/// - aucune fuite, ou service indisponible (on n'empêche pas l'inscription) ;
/// - compromis moins de 100 fois : seulement après confirmation explicite ;
/// - compromis 100 fois ou plus : refusé.
Future<bool> autoriserMotDePasse(BuildContext context, MotDePasseProvider verification, String motDePasse) async {
  final etat = await verification.verifierMotDePasse(motDePasse);
  if (!context.mounted) return false;
  if (etat != EtatVerificationMotDePasse.compromis) return true;
  final nombre = verification.nombreDerniereVerification;
  if (nombre >= MotDePasseService.seuilBlocage) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${messageCompromis(nombre)} Ce mot de passe ne peut pas être utilisé.')),
    );
    return false;
  }
  final confirme = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.gpp_maybe_outlined, color: _rouge),
      title: const Text('Mot de passe déjà exposé'),
      content: Text(
        '${messageCompromis(nombre)}\n\nVoulez-vous vraiment l’utiliser malgré ce risque ?',
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Choisir un autre')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Utiliser quand même')),
      ],
    ),
  );
  return confirme ?? false;
}
