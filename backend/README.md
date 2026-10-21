# Vérification de compte StudentHub

L'application continue d'enregistrer les comptes dans SQLite. Pour envoyer un
courriel automatique, elle appelle ce petit serveur, qui garde la cle Brevo
cote serveur. Ne mettez jamais `BREVO_API_KEY` dans Flutter ou dans le depot.

## Configurer Brevo

1. Creez un compte Brevo et activez l'envoi de courriels transactionnels.
2. Ajoutez et verifiez l'adresse expediteur (et, en production, authentifiez le
   domaine d'envoi).
3. Copiez `.env.example` en `.env`, puis renseignez `BREVO_API_KEY` et
   `BREVO_SENDER_EMAIL`. Le fichier `.env` est ignore par Git.
4. Utilisez Node.js 18 ou plus recent et lancez `node backend/welcome_mail_server.mjs`.
   Verifiez le service sur `/health`.
5. Hebergez ce serveur derriere HTTPS.
6. Lancez Flutter en fournissant l'URL publique :

   ```powershell
   flutter run --dart-define=ACCOUNT_API_URL=https://votre-api.example.com
   ```

Le parcours utilise `/verification-email` pour envoyer un code à 6 chiffres et
`/verify-email` pour le confirmer. Le code expire après 10 minutes. Il est
gardé en mémoire par le serveur : un redémarrage invalide les codes en cours.
Sans URL ou sans service mail, le compte reste localement en attente et ne peut
pas se connecter.

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
