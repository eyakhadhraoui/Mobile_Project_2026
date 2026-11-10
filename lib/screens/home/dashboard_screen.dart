import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/annonce_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/covoiturage_provider.dart';
import '../../providers/demande_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/api_client.dart';
import '../../services/housing_service.dart';
import '../../services/miroir_service.dart';
import '../announcements/announcements_screen.dart';
import '../chat/ai_chat_screen.dart';
import '../complaints/complaints_screen.dart';
import '../maintenance/demande_list_screen.dart';
import '../profile/profile_screen.dart';
import '../covoiturage/covoiturage_screen.dart';

/// Mode hors ligne et actions en attente, visibles depuis tous les onglets.
class _BandeauConnexion extends StatelessWidget {
  const _BandeauConnexion();

  @override
  Widget build(BuildContext context) {
    final annonces = context.watch<AnnonceProvider>();
    final refus = annonces.refusEnvoi;
    final attente = annonces.actionsEnAttente;
    if (refus == null && !annonces.horsLigne && attente == 0) {
      return const SizedBox.shrink();
    }
    final texte =
        refus ??
        [
          if (annonces.horsLigne) 'Hors ligne',
          if (attente > 0)
            '$attente à envoyer'
          else
            'données de l’appareil',
        ].join(' · ');
    final couleur = refus == null ? const Color(0xFF80550F) : const Color(0xFFC53030);
    return ColoredBox(
      color: refus == null ? const Color(0xFFFFF5E5) : const Color(0xFFFDECEC),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            Icon(refus == null ? Icons.cloud_off : Icons.error_outline, size: 16, color: couleur),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  texte,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: couleur, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: couleur,
              tooltip: refus == null ? 'Réessayer' : 'Fermer',
              onPressed: refus == null
                  ? () => annonces.charger().catchError((_) {})
                  : annonces.oublierRefusEnvoi,
              icon: Icon(refus == null ? Icons.refresh : Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  final _miroir = MiroirService();
  Timer? _minuteurMiroir;
  late final List<Widget> _pages = [
    const AnnouncementsScreen(),
    const CovoiturageScreen(),
    ComplaintsScreen(),
    const DemandeListScreen(),
    const AiChatScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = context.read<AuthProvider>().currentUserId;
      if (userId != null) {
        context.read<UserProvider>().load(userId);
        _preparerHorsLigne();
        _synchroniser();
        _minuteurMiroir = Timer.periodic(const Duration(seconds: 30), (_) => _synchroniser());
      }
    });
  }

  @override
  void dispose() {
    _minuteurMiroir?.cancel();
    super.dispose();
  }

  /// Garde SQLite et le JSON du serveur identiques, et rafraîchit les modules
  /// quand des données sont arrivées d'un autre téléphone.
  Future<void> _synchroniser() async {
    final userId = context.read<AuthProvider>().currentUserId;
    if (userId == null) return;
    final covoiturage = context.read<CovoiturageProvider>();
    final demandes = context.read<DemandeProvider>();
    try {
      if (await _miroir.synchroniser(userId) == 0) return;
      if (covoiturage.compte != null) await covoiturage.actualiser();
      await demandes.charger();
    } on ApiException {
      // Sans réseau : les changements partiront à la prochaine synchronisation.
    }
  }

  /// Garde une copie à jour des listes, pour pouvoir les ouvrir sans réseau
  /// même si elles n'ont pas été consultées avant la coupure.
  Future<void> _preparerHorsLigne() async {
    final housing = HousingService();
    try {
      await housing.visites();
      await housing.demandesLocation();
      await housing.disponibilites();
      await housing.activite();
    } on ApiException {
      // Sans réseau : les copies précédentes restent valables.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _BandeauConnexion(),
            Expanded(
              child: IndexedStack(index: _selectedIndex, children: _pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          // Maintenance et Profil affichent les logements loués : à jour à chaque visite.
          if (index == 3 || index == 5) {
            context.read<DemandeProvider>().chargerLogements();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_car_outlined),
            selectedIcon: Icon(Icons.directions_car),
            label: 'Covoiturage',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Réclamations',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: 'Maintenance',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Assistant IA',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
