# StudentHub

Application Flutter de gestion locale des utilisateurs et des réclamations.
Les données de compte sont enregistrées dans une base SQLite sur l'appareil, sans Firebase. Les réclamations restent consultables hors ligne dans SQLite ; une URL API HTTPS configurée permet leur synchronisation et leur consultation partagée.

## Fonctions disponibles

- Inscription avec nom, e-mail, téléphone et rôle (locataire, propriétaire ou prestataire).
- Connexion par e-mail ou téléphone et déconnexion.
- Mot de passe stocké sous forme dérivée avec PBKDF2 et sel individuel.
- Consultation et modification du profil, avec photo locale.
- Suppression du compte et de ses réclamations.
- Création, consultation, modification et suppression de réclamations.
- Catégories, référence de logement, photos, statut et historique des changements de statut.
- Brouillons locaux et file de synchronisation des réclamations.
- Consultation des réclamations synchronisées par tous les comptes utilisant la même API.

## Stockage

La base `studenthub.db` est créée automatiquement par `lib/services/app_database.dart`.
Elle comprend les tables `users`, `app_settings`, `complaints` et
`complaint_history`. Les photos choisies sont copiées dans le répertoire privé de
l'application et leurs chemins sont conservés dans SQLite. Les photos ne sont pas envoyées au serveur et restent visibles uniquement sur l'appareil d'origine.

## Mode hors ligne et partage des réclamations

La liste affiche d'abord le cache SQLite, même sans Internet. Un brouillon reste sur l'appareil et n'est pas synchronisé. Une réclamation envoyée hors ligne reste marquée « À synchroniser » ; l'application réessaie au retour dans l'application et toutes les 30 secondes tant que la liste est ouverte. Les réclamations reçues du serveur sont ensuite gardées dans le cache local.

Pour activer le partage, suivez `backend/README.md`, déployez `backend/welcome_mail_server.mjs` sur une URL HTTPS avec stockage persistant, puis lancez Flutter avec `--dart-define=ACCOUNT_API_URL=https://votre-api`. Sans URL API, les réclamations restent locales. L'API de démonstration ne vérifie pas l'identité des comptes : ne l'exposez pas avec des données privées sans ajouter une authentification côté serveur.

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
