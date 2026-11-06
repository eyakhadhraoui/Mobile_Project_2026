import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/annonce_provider.dart';

/// Relance le planificateur des annonces programmées quand l'application
/// revient au premier plan (AppLifecycleState.resumed). Le démarrage et le
/// passage toutes les 30 secondes sont gérés par [AnnonceProvider].
class PlanificateurAnnonces extends StatefulWidget {
  const PlanificateurAnnonces({super.key, required this.child});
  final Widget child;

  @override
  State<PlanificateurAnnonces> createState() => _PlanificateurAnnoncesState();
}

class _PlanificateurAnnoncesState extends State<PlanificateurAnnonces> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<AnnonceProvider>().rafraichir();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
