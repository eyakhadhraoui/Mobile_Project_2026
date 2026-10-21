# StudentHub

Application Flutter de gestion locale des utilisateurs et des réclamations.
Les données sont enregistrées dans une base SQLite sur l'appareil, sans Firebase
ni synchronisation entre appareils.

## Fonctions disponibles

- Inscription avec nom, e-mail, téléphone et rôle (locataire, propriétaire ou prestataire).
- Connexion par e-mail ou téléphone et déconnexion.
- Mot de passe stocké sous forme dérivée avec PBKDF2 et sel individuel.
- Consultation et modification du profil, avec photo locale.
- Suppression du compte et de ses réclamations.
- Création, consultation, modification et suppression de réclamations.
- Catégories, référence de logement, photos, statut et historique des changements de statut.

## Stockage

La base `studenthub.db` est créée automatiquement par `lib/services/app_database.dart`.
Elle comprend les tables `users`, `app_settings`, `complaints` et
`complaint_history`. Les photos choisies sont copiées dans le répertoire privé de
l'application et leurs chemins sont conservés dans SQLite.

Les références de logement sont saisies dans le formulaire. Le module Locations
et la vérification qu'une location est active ne font pas partie de cette version.
La réinitialisation du mot de passe par e-mail nécessite un serveur et n'est donc
pas disponible en mode SQLite local.

## Lancer l'application

```bash
flutter pub get
flutter run
```

La base `sqflite` est prévue pour Android, iOS et macOS. Le cahier des charges
vise Android 8 et plus ; cette version ne configure pas le stockage SQLite pour
le Web ni pour Windows/Linux.
