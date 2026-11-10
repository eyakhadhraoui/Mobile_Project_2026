import 'dart:async';

import 'package:flutter/material.dart';

/// `1 j 02 h 05 min 09 s` ; les unités nulles de tête sont omises.
String formatDuree(Duration duree) {
  String deux(int n) => n.toString().padLeft(2, '0');
  final jours = duree.inDays;
  final heures = duree.inHours % 24;
  final minutes = duree.inMinutes % 60;
  final secondes = duree.inSeconds % 60;
  if (jours > 0) return '$jours j ${deux(heures)} h ${deux(minutes)} min';
  if (heures > 0) return '$heures h ${deux(minutes)} min ${deux(secondes)} s';
  if (minutes > 0) return '$minutes min ${deux(secondes)} s';
  return '$secondes s';
}

/// Temps restant avant [date], actualisé chaque seconde.
///
/// [date] est un instant absolu : le décompte reste juste quel que soit le
/// fuseau horaire du téléphone.
class CompteARebours extends StatefulWidget {
  const CompteARebours({
    super.key,
    required this.date,
    this.prefixe = '',
    this.couleur,
    this.onTermine,
    this.horloge = DateTime.now,
  });

  final DateTime date;
  final String prefixe;
  final Color? couleur;

  /// Appelé une seule fois, juste après l'échéance.
  final VoidCallback? onTermine;
  final DateTime Function() horloge;

  @override
  State<CompteARebours> createState() => _CompteAReboursState();
}

class _CompteAReboursState extends State<CompteARebours> {
  // Le serveur publie dès que l'heure est passée : on lui laisse une seconde
  // d'avance pour que le rechargement trouve bien l'annonce publiée.
  static const _margeServeur = Duration(seconds: 1);

  Timer? _timer;

  Duration get _restant => widget.date.difference(widget.horloge());

  @override
  void initState() {
    super.initState();
    _demarrer();
  }

  @override
  void didUpdateWidget(CompteARebours ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.date != widget.date) _demarrer();
  }

  void _demarrer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tic());
  }

  void _tic() {
    if (_restant <= -_margeServeur) {
      _timer?.cancel();
      widget.onTermine?.call();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restant = _restant;
    return Text(
      restant.inSeconds <= 0
          ? 'Publication en cours…'
          // Arrondi supérieur : on n'affiche jamais « 0 s » avant l'échéance.
          : '${widget.prefixe}${formatDuree(restant + const Duration(milliseconds: 999))}',
      style: TextStyle(
        color: widget.couleur,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
