
# StudentHub

Application mobile Flutter pour la vie étudiante : logement, covoiturage, réclamations, maintenance et messagerie entre locataires et propriétaires. Un serveur Node local partage les données entre les comptes et appelle l'IA.

## Modules

| Module | Fonctions principales |
|---|---|
| Comptes | Inscription avec code e-mail, connexion par e-mail ou téléphone, mot de passe oublié, profil, rôles (locataire, propriétaire, prestataire, administrateur), validation et blocage des comptes |
| Annonces | Logements, résidences, événements, avis ; filtres, carte, favoris, commentaires, notes, visites, demandes de location, publication programmée |
| Covoiturage | Offres et demandes de trajets, réservations, carte, alertes, évaluations des conducteurs |
| Réclamations | Création avec photos et brouillon, statuts, historique, échanges traduits, carte, incidents collectifs |
| Maintenance | Demandes d'intervention, attribution à un prestataire, suivi des statuts |
| Messagerie | Discussion liée à une annonce, photos, traduction automatique |
| Assistant IA | Chatbot général et assistant de réclamations |

## Fonctions avancées

| Fonction | Fichiers |
|---|---|
| Estimation du loyer calculée sur le téléphone, sans réseau | `lib/services/estimation_prix_service.dart`, `assets/modele_prix.json`, `tool/entrainement_prix/entrainer.mjs` |
| Refus des photos déjà publiées dans une autre annonce | `backend/detection_photos.mjs` |
| Tri des réclamations par IA (catégorie, priorité, titre) | `lib/services/tri_reclamation_service.dart` |
| Détection de danger (gaz, électricité, incendie, inondation) : priorité urgente imposée par une règle | `lib/core/utils/detecteur_danger.dart` |
| Incidents collectifs : au moins 2 signalements du même bâtiment en 48 h | `lib/services/incident_service.dart` |
| Assistant réclamations appuyé sur une base de connaissances (RAG) | `backend/assistant_reclamations.mjs`, `backend/knowledge/` |
| Analyse d'une photo de panne pour pré-remplir la demande | `lib/services/gemini_service.dart`, route `POST /maintenance/analyze` |
| Correspondance automatique entre offres et demandes de covoiturage | `lib/services/covoiturage_alertes.dart` |
| Visites : météo prévue et jours fériés | `lib/services/visit_weather_service.dart`, `lib/services/public_holidays_service.dart` |
| Mode hors ligne : files d'envoi et synchronisation | `lib/services/annonce_file_service.dart`, `lib/services/complaint_service.dart` |
| Double stockage SQLite ↔ JSON du serveur | `lib/services/miroir_service.dart`, `backend/miroir.mjs` |
| Mots de passe : PBKDF2 sur le téléphone, scrypt sur le serveur, contrôle des fuites connues | `lib/services/auth_service.dart`, `lib/services/mot_de_passe_service.dart` |

## Architecture

```
Écran (StatefulWidget) → Provider (ChangeNotifier) → Service → SQLite (sqflite) et/ou serveur Node
```

- **Flutter :** `lib/screens` (interface), `lib/providers` (état), `lib/services` (accès aux données), `lib/models`.
- **Base locale :** SQLite via sqflite, schéma et migrations dans `lib/services/database_helper.dart`, clés étrangères activées.
- **Serveur :** Node sans framework, entrée `backend/welcome_mail_server.mjs`, données en JSON dans `backend/data/` (ignoré par Git).
- **Sécurité :** les clés d'API restent sur le serveur. L'application ne parle qu'au serveur StudentHub, et seul le serveur appelle Gemini.

## Installation

### Prérequis

- Flutter avec Dart `^3.13.4`
- Node.js 22
- Un émulateur Android ou un téléphone

### 1. Serveur

```powershell
cd backend
npm install
copy .env.example .env
npm start
```

Renseigne `.env`. Ne le partage jamais : il est ignoré par Git.

| Variable | Rôle |
|---|---|
| `PORT` | Port du serveur. Mets `6500`, la valeur attendue par l'application (le serveur utilise 3000 par défaut). |
| `GMAIL_SMTP_USER`, `GMAIL_SMTP_APP_PASSWORD`, `GMAIL_SMTP_SENDER_NAME` | Envoi des codes de vérification par e-mail |
| `GEMINI_API_KEY`, `GEMINI_MODEL` | IA : analyse de photo, assistant réclamations, détection de doublons |
| `OPENAI_API_KEY`, `OPENAI_MODEL` | Route `/chat`, utilisée par le chatbot général et le tri des réclamations. Sans clé, ces deux fonctions répondent « non configuré ». |
| `ADMIN_EMAILS` | Adresses des administrateurs, séparées par des virgules |
| `AUTH_SECRET` | Secret de signature des jetons, 32 caractères minimum. S'il est absent, il est généré une fois et conservé dans `data/`. |
| `DATA_DIR` | Dossier des données (par défaut `backend/data`) |

Le serveur lit `.env` au démarrage : redémarre-le après chaque modification.

### 2. Application

```powershell
flutter pub get
flutter run --dart-define=ACCOUNT_API_URL=http://10.0.2.2:6500 --dart-define=ALLOW_INSECURE_MAIL_API=true
```

`10.0.2.2` désigne l'ordinateur depuis l'émulateur Android. Sans ces deux options, l'analyse de photo et l'envoi des e-mails ne sont pas configurés. Hors debug, l'adresse du serveur doit être en HTTPS.

## Données de démonstration

```powershell
cd backend
npm run seed:demo
```

Tous les comptes de démo utilisent le mot de passe `Demo2026!` :

| Compte | Rôle |
|---|---|
| `sami.bensalah@studenthub.test` | Propriétaire |
| `leila.trabelsi@studenthub.test` | Propriétaire |
| `karim.jaziri@studenthub.test` | Propriétaire |
| `yasmine.gharbi@studenthub.test` | Locataire |
| `omar.mansouri@studenthub.test` | Locataire (loue un logement : peut créer des demandes de maintenance) |
| `anna.petrova@studenthub.test` | Locataire (écrit en anglais : pour tester la traduction) |
| `mehdi.ayari@studenthub.test` | Prestataire |
| `admin@studenthub.test` | Administrateur, seulement si son adresse figure dans `ADMIN_EMAILS` |

Les crédits des photos de démo sont dans `backend/CREDITS_PHOTOS.md`.

## Tests

```powershell
flutter analyze
flutter test
cd backend; npm test
node --test tool/entrainement_prix
```

Les tests n'appellent jamais la vraie API Gemini.

## Voir la base SQLite

Sur l'émulateur, la base est dans `/data/data/com.example.studenthub/databases/studenthub.db`. Ouvre-la dans Android Studio avec **View > Tool Windows > App Inspection > Database Inspector**, pendant que l'application tourne.

## Limites connues

- Les routes `/complaints` du serveur ne demandent pas de jeton.
- Tous les comptes voient la liste complète des réclamations, sauf les brouillons des autres.
- « Supprimer mon compte » efface les données du téléphone, pas le compte sur le serveur.
- Un changement d'e-mail ou de téléphone dans le profil reste local.
- Les photos des réclamations ne sont pas envoyées au serveur.
- Il n'y a pas de notification lors d'un changement de statut de réclamation, même si l'écran de confirmation l'annonce.
- Une demande de maintenance ne peut être attribuée qu'à un prestataire qui s'est déjà connecté sur le même téléphone.

## Documentation complémentaire

- `backend/README.md` : routes du serveur, assistant réclamations, analyse de photo, messagerie, détection de doublons, double stockage.
