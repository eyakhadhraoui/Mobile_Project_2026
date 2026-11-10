# Serveur StudentHub

Serveur Node local utilisé par l'application Flutter.

```powershell
cd backend
npm install
npm start
```

## Configuration

Copie `.env.example` vers `.env`, puis renseigne les valeurs. Le fichier `.env` est ignoré par Git : ne le partage jamais.

Le serveur lit `.env` une seule fois au démarrage : redémarre-le après chaque modification.

Variables utilisées par l'analyse de photo :

| Variable | Rôle |
|---|---|
| `GEMINI_API_KEY` | Clé de l'API Gemini. Elle reste sur le serveur, jamais dans l'application. |
| `GEMINI_MODEL` | Nom du modèle Gemini à appeler. |

## Administration des comptes

`ADMIN_EMAILS` liste les adresses administrateurs, séparées par des virgules. Une liste non vide active aussi la modération des annonces.

| Route | Rôle |
|---|---|
| `GET /admin/users` | Liste des comptes (administrateur) |
| `POST /admin/users/:id/statut` | `{ "statut": "approved" \| "pending" \| "blocked" }` (administrateur) |
| `POST /auth/password-reset` | `{ "verificationToken", "password" }` après saisie du code e-mail |

Un compte bloqué ou en attente reçoit `403` (`account_blocked`, `account_pending`) à la connexion et sur toute route authentifiée. Une réinitialisation ferme les sessions ouvertes avant elle.

## Assistant réclamations

Utilise `GEMINI_API_KEY` et `GEMINI_MODEL`, réservé aux locataires et propriétaires. Tests : `npm test` (aucun appel à Gemini).

| Route | Rôle |
|---|---|
| `GET /assistant/conversations` | Historique de l'utilisateur (sans les messages) |
| `POST /assistant/conversations` | `{ "message" }` : nouvelle réclamation analysée |
| `GET /assistant/conversations/:id` | Conversation complète |
| `POST /assistant/conversations/:id/messages` | `{ "message" }` : message suivant |
| `POST /assistant/conversations/:id/statut` | `{ "statut": "ouverte" \| "en_cours" \| "resolue" }` |
| `DELETE /assistant/conversations/:id` | Suppression |

La base documentaire est dans `knowledge/*.md` et chargée au démarrage. Le format est décrit en tête de `knowledge/guides_pratiques.md`. Les guides fournis sont des conseils pratiques et ne citent aucune loi : pour la réglementation, ajoutez des extraits officiels vérifiés. Une référence juridique absente des documents est retirée de la réponse de l'IA.

## POST /maintenance/analyze

Analyse une photo de problème de logement pour pré-remplir une demande de maintenance.

Corps JSON, 8 Mo maximum :

```json
{ "imageBase64": "...", "mimeType": "image/jpeg" }
```

`mimeType` accepte `image/jpeg`, `image/png` et `image/webp`.

Réponse 200 :

```json
{
  "is_maintenance_issue": true,
  "category": "plomberie",
  "room": "cuisine",
  "urgency": "elevee",
  "title": "Fuite sous l'évier",
  "description": "Une fuite d'eau est visible sous l'évier de la cuisine."
}
```

Si la photo ne montre pas de problème de logement, `is_maintenance_issue` vaut `false` et les autres champs valent `null`. Une catégorie, une pièce ou une urgence hors liste, un titre hors 5-100 caractères ou une description hors 15-500 caractères sont remplacés par `null`.

| Code | `error` | Cause |
|---|---|---|
| 400 | `invalid_request` | JSON invalide, ou `imageBase64` vide ou absent |
| 413 | `image_too_large` | Corps supérieur à 8 Mo |
| 415 | `unsupported_image` | Type d'image non accepté |
| 429 | `rate_limited` | Plus de 30 appels à Gemini par heure et par IP |
| 502 | `analysis_failed` | Erreur de Gemini, délai de 45 s dépassé ou réponse illisible |
| 503 | `analysis_not_configured` | `GEMINI_API_KEY` ou `GEMINI_MODEL` absent |

Le serveur ne journalise jamais la clé ni le contenu des images.

## Messagerie locataire ↔ propriétaire

Routes authentifiées (`backend/messagerie.mjs`), réservées aux deux participants :

| Méthode | Route | Rôle |
|---|---|---|
| GET | `/conversations` | Conversations ayant au moins un message, avec le nombre de non-lus |
| POST | `/conversations` | `{ annonceId, locataireId? }` : retrouve ou crée la conversation |
| GET | `/conversations/:id/messages` | 200 derniers messages (ETag, 304 si rien de nouveau) |
| POST | `/conversations/:id/messages` | `{ texte?, photos?, langue?, clientId? }` : `clientId` évite les doublons |

Le propriétaire n'écrit le premier qu'à une personne ayant demandé une visite ou une location. Données : `data/conversations.json` et `data/messages.json`.

## Fiabilité des annonces : photos déjà publiées

`backend/detection_photos.mjs` compare chaque photo aux images des annonces des autres comptes (empreintes dans `data/empreintes_photos.json`). Une photo identique ou très proche (distance pHash ≤ 6), ou confirmée par Gemini dans la zone douteuse (≤ 14), est refusée : `POST` et `PUT /annonces` répondent 409 `photo_deja_publiee`. `POST /photos/verifier` fait le même contrôle dès l'ajout, sans conserver l'image. La bibliothèque `sharp` s'installe avec `npm install` dans `backend`.

## Double stockage SQLite et JSON

`POST /miroir/synchroniser` (`backend/miroir.mjs`, `lib/services/miroir_service.dart`) garde les deux côtés identiques : les tables locales (covoiturage, maintenance, logements loués, caches) sont écrites dans `data/<table>.json`, et les données du serveur (visites, disponibilités, demandes, likes, commentaires, avis, messagerie, chatbot) sont recopiées dans SQLite. Chaque compte ne reçoit et ne modifie que ce qui le concerne. Les mots de passe, les jetons, `app_settings` et `auth_secret.txt` ne sont jamais copiés.
