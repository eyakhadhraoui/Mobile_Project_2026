import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/annonce_provider.dart';
import 'providers/complaint_provider.dart';
import 'providers/trajet_provider.dart';
import 'providers/user_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/dashboard_screen.dart';
import 'services/heure_service.dart';
import 'services/notification_service.dart';
import 'widgets/planificateur_annonces.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Notifications des annonces programmées (fuseau horaire + canal Android).
  // Sans attendre : une erreur ici ne doit pas empêcher l'ouverture de l'application.
  NotificationsLocales.instance.initialiser().catchError(
    (Object error) => debugPrint('Notifications indisponibles : $error'),
  );
  runApp(const StudentHubApp());
}

class StudentHubApp extends StatelessWidget {
  const StudentHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // Heure officielle partagée (formulaire d'annonce et planificateur).
        Provider<HeureService>(create: (_) => HeureService(), dispose: (_, service) => service.fermer()),
        // Les annonces suivent la session : chargement à la connexion, vidage à la déconnexion.
        ChangeNotifierProxyProvider<AuthProvider, AnnonceProvider>(
          create: (context) => AnnonceProvider(
            heure: context.read<HeureService>(),
            notifications: NotificationsLocales.instance,
          ),
          update: (_, auth, annonces) =>
              (annonces ?? AnnonceProvider())..utilisateur(auth.currentUserId),
        ),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        // Temps de trajet logement → université (Nominatim + OSRM, cache SQLite).
        ChangeNotifierProvider(create: (_) => TrajetProvider()),
        ChangeNotifierProvider(create: (_) => ComplaintProvider()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const PlanificateurAnnonces(child: _AuthGate()),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (!auth.isInitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return auth.isAuthenticated
            ? const DashboardScreen()
            : const LoginScreen();
      },
    );
  }
}
