import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../complaints/complaints_screen.dart';
import '../profile/profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _pages = [
    _HomeTab(onOpenComplaints: () => setState(() => _selectedIndex = 1)),
    ComplaintsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = context.read<AuthProvider>().currentUserId;
      if (userId != null) context.read<UserProvider>().load(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Réclamations',
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

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.onOpenComplaints});

  final VoidCallback onOpenComplaints;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;
    final theme = Theme.of(context);
    final name = user == null ? '' : user.prenom;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.home_work_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'StudentHub',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 34),
          Text(
            name.isEmpty ? 'Bienvenue !' : 'Bonjour, $name !',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Votre logement et vos demandes, au même endroit.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Besoin d’aide ?',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Signalez un problème dans votre logement et suivez son traitement.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: onOpenComplaints,
                        icon: const Icon(Icons.add),
                        label: const Text('Mes réclamations'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.home_repair_service_outlined,
                  size: 54,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.storage_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Mode local'),
              subtitle: const Text(
                'Vos données SQLite sont enregistrées sur cet appareil.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
