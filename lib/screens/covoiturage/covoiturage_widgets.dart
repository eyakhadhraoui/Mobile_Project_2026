import 'package:flutter/material.dart';

import '../../models/enums_covoiturage.dart';

/// `2026-11-09` devient `09/11/2026`.
String dateTrajet(String iso) {
  final parties = iso.split('-');
  return parties.length == 3
      ? '${parties[2]}/${parties[1]}/${parties[0]}'
      : iso;
}

Color couleurStatutTrajet(StatutTrajetEnum statut) => switch (statut) {
  StatutTrajetEnum.ouvert => const Color(0xFF2F855A),
  StatutTrajetEnum.annule => const Color(0xFFC53030),
  _ => const Color(0xFF66748A),
};

/// Départ et destination l'un sous l'autre, reliés par une ligne.
class ItineraireTrajet extends StatelessWidget {
  const ItineraireTrajet({
    super.key,
    required this.depart,
    required this.arrivee,
    this.style,
  });

  final String depart, arrivee;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final texte = style ?? Theme.of(context).textTheme.titleMedium;
    Widget lieu(String nom) => Text(
      nom,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: texte,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              children: [
                Icon(
                  Icons.radio_button_checked,
                  size: 16,
                  color: couleurs.primary,
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: couleurs.outlineVariant,
                  ),
                ),
                Icon(Icons.location_on, size: 18, color: couleurs.error),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [lieu(depart), const SizedBox(height: 14), lieu(arrivee)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Petite étiquette arrondie : type, statut, date, places…
class PastilleTrajet extends StatelessWidget {
  const PastilleTrajet({
    super.key,
    required this.texte,
    this.icone,
    this.couleur,
  });

  final String texte;
  final IconData? icone;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final teinte = couleur ?? const Color(0xFF66748A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: teinte.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 14, color: teinte),
            const SizedBox(width: 5),
          ],
          Text(
            texte,
            style: TextStyle(
              color: teinte,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
