# Vérification de compte StudentHub

Le serveur Node envoie les courriels par Gmail SMTP. Le mot de passe
d'application est lu uniquement depuis `backend/.env`. Ne le mettez jamais dans
 Flutter, dans Git ou dans un message.

## Configurer Gmail SMTP

1. Sur le compte Google d'envoi, activez la validation en deux étapes puis créez
   un mot de passe d'application. Comme le mot de passe déjà partagé dans le
   chat est exposé, révoquez-le et créez-en un nouveau.
2. Dans `backend/.env`, configurez :

   ```env
   PORT=6500
   GMAIL_SMTP_USER=votre-adresse@gmail.com
   GMAIL_SMTP_APP_PASSWORD=mot_de_passe_application
   GMAIL_SMTP_SENDER_NAME=StudentHub
   ```

   Gmail retire les espaces du mot de passe d'application. Gardez `backend/.env`
   privé : il est ignoré par Git.
3. Installez la dépendance et lancez le serveur depuis `backend` :

   ```powershell
   npm install
   npm start
   ```

4. Vérifiez `http://localhost:6500/health`. Pour l'émulateur Android en
   développement, lancez Flutter depuis la racine du projet :

   ```powershell
   flutter run -d emulator-5554 --dart-define=ACCOUNT_API_URL=http://10.0.2.2:6500 --dart-define=ALLOW_INSECURE_MAIL_API=true
   ```

   Pour un téléphone sur le même Wi-Fi, utilisez l'adresse IP locale du PC.
   Pour une version distribuée, hébergez le serveur derrière HTTPS.
Le parcours utilise `/verification-email` pour envoyer un code à 6 chiffres et
`/verify-email` pour le confirmer. Le code expire après 10 minutes. Il est
gardé en mémoire par le serveur : un redémarrage invalide les codes en cours.
Sans URL ou sans service mail, l'inscription est interrompue et aucun compte
n'est créé. L'émulateur Android ne peut pas joindre le `localhost` de Windows ;
utilisez une URL publique HTTPS pour le serveur.

Le serveur limite les envois a dix par heure et par adresse IP. Pour une mise
en production publique, ajoutez une protection anti-abus adaptée à votre
hébergeur. La base des comptes reste SQLite sur chaque appareil : les actions
administrateur ne sont donc visibles que sur l'appareil qui contient cette base.
Pour un déploiement multi-utilisateur, il faudra transférer comptes et rôles
vers une base serveur partagée et protéger l'administration par une connexion
administrateur côté serveur.

## Activer l'écran d'administration pour une démonstration locale

L'inscription publique ne propose jamais le rôle administrateur. Pour une
démonstration sur émulateur, créez d'abord un compte normal, récupérez
`studenthub.db` depuis Android Studio > Device Explorer >
`data/data/com.example.studenthub/databases/`, puis ouvrez-le avec DB Browser
for SQLite. Dans l'onglet d'exécution SQL, attribuez le rôle au compte choisi :

```sql
UPDATE users SET rolePrincipal = 'administrateur', emailVerified = 1,
  accountStatus = 'approved' WHERE email = 'votre-adresse@example.com';
```

Replacez la base dans l'émulateur et reconnectez ce compte. L'option « Gestion
des comptes » apparaît sur son profil. Ceci convient à une maquette locale,
pas à une application publiée.

## Mode hors ligne et synchronisation des reclamations

L'application lit d'abord les reclamations depuis SQLite. Les brouillons restent locaux et sont visibles seulement par leur auteur sur cet appareil. Les demandes envoyees sont placees dans une file locale lorsqu'aucune connexion n'est disponible; l'application retente la synchronisation au retour au premier plan et toutes les 30 secondes tant que la liste des reclamations est ouverte.

Avec `ACCOUNT_API_URL` configure en HTTPS, `GET /complaints` recupere les demandes partagees et `POST /complaints` synchronise les nouvelles demandes et leurs changements de statut. Les donnees partagees sont conservees dans `backend/data/complaints.json`; configurez un stockage persistant sur l'hebergeur et ne versionnez pas ce fichier. Les photos restent locales et ne sont pas partagees.

Tous les utilisateurs connectes a la meme API voient les reclamations synchronisees. Les comptes et les brouillons restent dans le SQLite local. L'API de partage de demonstration n'est pas authentifiee; elle ne convient pas a un deploiement contenant des renseignements prives sans ajout d'une authentification serveur et de regles d'acces.

## Annonces partagées (API authentifiée)

Les annonces, leurs photos, likes, commentaires et avis, ainsi que les
disponibilités, visites et demandes de location, sont stockés par le serveur et
partagés entre tous les appareils qui utilisent la même `ACCOUNT_API_URL`.

### Comptes et sécurité

- À l'inscription, le code e-mail renvoie un jeton de vérification ; le compte
  est alors créé aussi sur le serveur (`POST /auth/register`, mot de passe haché
  avec scrypt).
- À la connexion, l'application obtient un jeton de session signé (30 jours),
  envoyé dans l'en-tête `Authorization: Bearer …`. L'identité de l'auteur d'un
  like, d'un commentaire, d'un avis ou d'une annonce vient toujours de ce jeton,
  jamais du corps de la requête.
- **Comptes créés avant cette version** : à la première connexion, l'application
  demande de confirmer l'adresse e-mail par code pour créer le compte serveur.
  Les annonces que ce compte avait en local sont ensuite envoyées
  automatiquement au serveur, avec leurs photos, puis retirées de l'appareil.
- Sans serveur joignable, la connexion reste possible hors ligne (réclamations
  locales), mais les annonces affichent « Serveur injoignable ».

Variables facultatives dans `backend/.env` :

```env
# Adresses e-mail administrateurs (séparées par des virgules). Si la liste est
# vide, les annonces sont publiées sans modération.
ADMIN_EMAILS=admin@exemple.com
# Secret de signature des jetons (32 caractères minimum). Sinon, un secret est
# généré une fois dans data/auth_secret.txt.
AUTH_SECRET=une_longue_chaine_aleatoire
# Dossier de données (par défaut backend/data)
DATA_DIR=
```

### Modération

Avec `ADMIN_EMAILS` renseigné, une nouvelle annonce (ou une annonce modifiée)
reste « En attente de validation » : seuls son auteur et les administrateurs la
voient. Un administrateur la publie ou la refuse avec un motif depuis le détail
de l'annonce (filtre « À modérer »). L'auteur peut archiver puis republier son
annonce.

### Publication programmée

L'auteur choisit une date et une heure (champ `datePublication`, ISO 8601 UTC,
strictement future et à un an maximum). L'annonce reste au statut `programmee`,
visible seulement par son auteur et les administrateurs. Avant chaque requête,
le serveur publie les annonces échues : `publiee`, ou `enAttente` si la
modération est active et que l'auteur n'est pas administrateur. Les autres
utilisateurs la voient donc à l'heure prévue, même si le téléphone de l'auteur
est éteint.

`POST /annonces/:id/programmation` avec `{ "datePublication": "…" }` programme ou
reprogramme ; avec `{ "datePublication": null, "publierMaintenant": true|false }`
annule (publication immédiate ou retour « en attente »). Envoyer
`datePublication: null` dans `PUT /annonces/:id` annule aussi la programmation.

Côté application : l'heure officielle vient de
`https://timeapi.io/api/Time/current/zone?timeZone=Africa/Tunis` (repli sur
l'horloge du téléphone). Un planificateur local met à jour la copie SQLite au
démarrage, au retour au premier plan et toutes les 30 secondes. Une notification
locale est programmée à l'heure exacte (Android 12+ : autorisation des
notifications et des alarmes exactes ; si elle est refusée, la publication a
quand même lieu et l'application rattrape l'état à l'ouverture).

### Données

Fichiers JSON dans `backend/data/` : `users`, `annonces`,
`announcement_interactions`, `ratings`, `availability`, `visits`,
`rental_requests`, `photos` (index), et le dossier `photos/` (images JPEG, PNG
ou WebP, 6 Mo maximum, vérifiées par leur contenu). Conservez ce dossier sur un
stockage persistant et sauvegardez-le.

### Principales routes

| Méthode | Route | Rôle |
|---|---|---|
| POST | `/auth/register`, `/auth/login` | Compte serveur et jeton |
| GET/PUT | `/me` | Profil serveur (nom affiché) |
| GET | `/annonces` | Liste visible + statistiques (ETag : `304` si rien n'a changé) |
| POST/PUT/DELETE | `/annonces`, `/annonces/:id` | Créer, modifier, supprimer (auteur) |
| POST | `/annonces/:id/statut` | Publier / refuser (admin), archiver (auteur) |
| POST | `/annonces/:id/programmation` | Programmer, reprogrammer ou annuler la publication (auteur) |
| POST | `/annonces/:id/avis` | Note 1 à 5 (une par utilisateur, pas l'auteur) |
| GET/POST | `/annonces/:id/interactions` | Likes et commentaires |
| GET | `/annonces/:id/creneaux` | Créneaux de visite libres |
| GET/POST/DELETE | `/disponibilites` | Plages de visite du propriétaire |
| GET/POST | `/visites`, `/visites/:id/statut` | Réserver, lister, annuler |
| GET/POST | `/demandes-location`, `/demandes-location/:id/statut` | Demander, accepter, refuser, annuler |
| GET | `/activite` | Activité sur mes annonces et réponses à mes demandes |
| POST/GET | `/photos`, `/photos/:nom` | Envoi et lecture des photos |

La gestion des disponibilités interroge Nager.Date pour chaque année couverte
(cache mémoire par année) et conserve les dates fériées retenues dans la plage.
Ces dates sont retirées de la génération des créneaux; si l'API est indisponible,
la plage est créée sans exclusion et l'application affiche un avertissement.
La confirmation d'une visite affiche les prévisions Open-Meteo quand la date est
dans la période disponible (jusqu'à 16 jours); passé ce délai, elle indique que
la météo n'est pas disponible pour cette date.

L'ancienne route non authentifiée `/announcements/:id/interactions` a été
supprimée ; les likes et commentaires existants sont conservés.

## Assistant IA

L'onglet **Assistant IA** est disponible pour tous les comptes connectés. Pour activer
les réponses, créez une clé API sur la plateforme OpenAI puis ajoutez-la au fichier
`backend/.env` (gardez cette clé privée et ne la mettez jamais dans Flutter) :

```env
OPENAI_API_KEY=votre_cle_api
OPENAI_MODEL=gpt-5.4-mini
```

Lancez le serveur depuis le dossier `backend` avec `npm start`, puis relancez Flutter
avec l'URL du serveur déjà utilisée pour l'e-mail :

```powershell
flutter run -d emulator-5554 --dart-define=ACCOUNT_API_URL=http://10.0.2.2:6500 --dart-define=ALLOW_INSECURE_MAIL_API=true
```

L'appel IA passe par l'API Responses et la clé reste côté serveur. L'utilisation de
l'API peut entraîner des frais selon votre compte OpenAI.
