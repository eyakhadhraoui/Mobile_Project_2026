import { randomBytes } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, readFile, stat, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';

import { createAssistantRoutes } from './assistant_reclamations.mjs';
import { checkPassword, hashPassword, signToken, verifyToken } from './auth.mjs';
import { analyserImage, chercherProches, creerArbitre, estConfirme, SEUIL_CERTAIN } from './detection_photos.mjs';
import { createMessagerieRoutes } from './messagerie.mjs';
import { createMiroirRoutes } from './miroir.mjs';
import { createStore } from './store.mjs';

const ID = /^[A-Za-z0-9_-]{1,100}$/;
const PHOTO_PATH = /^\/photos\/([a-f0-9]{32}\.(?:jpg|png|webp))$/;
const CATEGORIES = ['Logement', 'Résidence', 'Événement', 'Avis', 'Autre'];
const TYPES_LOGEMENT = ['Studio', 'Chambre', 'Colocation', 'Appartement', 'Maison'];
// « programmee » n'est pas modifiable par /statut : voir /annonces/:id/programmation.
const STATUTS = ['enAttente', 'publiee', 'archivee'];
const MAX_PROGRAMMATION = 366 * 24 * 60 * 60 * 1000;
const ROLES_PUBLICS = ['locataire', 'proprietaire', 'prestataire'];
const FREQUENCES = ['MONTHLY', 'QUARTERLY', 'SEMI_ANNUALLY', 'ANNUALLY'];
const MOYENS = ['BANK_TRANSFER', 'CHEQUE', 'CASH', 'OTHER'];
const DAY = 24 * 60 * 60 * 1000;

class HttpError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const fail = (status, code, message) => { throw new HttpError(status, code, message); };

function respond(res, status, body, headers = {}) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers });
  res.end(body === undefined ? undefined : JSON.stringify(body));
}

async function readBody(req, limit) {
  const chunks = []; let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) fail(413, 'too_large', 'Contenu trop volumineux.');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}
async function readJson(req) {
  try {
    const value = JSON.parse((await readBody(req, 100 * 1024)).toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    fail(400, 'invalid_request', 'Requête invalide.');
  }
}

const text = (value, min, max, label) => {
  const result = typeof value === 'string' ? value.trim() : '';
  if (result.length < min || result.length > max) {
    fail(400, 'invalid_field', min > 0 ? `${label} : entre ${min} et ${max} caractères.` : `${label} : ${max} caractères maximum.`);
  }
  return result;
};
const number = (value, min, max, label, integer = false) => {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max || (integer && !Number.isInteger(value))) {
    fail(400, 'invalid_field', `${label} invalide (entre ${min} et ${max}).`);
  }
  return value;
};
const pad = (n) => String(n).padStart(2, '0');
const isDate = (value) => {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d;
};
const isTime = (value) => typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
const minutes = (time) => Number(time.slice(0, 2)) * 60 + Number(time.slice(3, 5));
const clock = (total) => `${pad(Math.floor(total / 60))}:${pad(total % 60)}`;
const addDays = (date, n) => {
  const [y, m, d] = date.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
};
const daysBetween = (from, to) => Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY);
/** Heure locale du serveur, au même format « naïf » que les créneaux (AAAA-MM-JJTHH:MM). */
const localNow = () => {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
const newId = () => `${Date.now().toString(36)}${randomBytes(6).toString('hex')}`;

function sniffImage(buffer) {
  if (buffer.length > 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'jpg';
  if (buffer.length > 8 && buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (buffer.length > 12 && buffer.toString('ascii', 0, 4) === 'RIFF' && buffer.toString('ascii', 8, 12) === 'WEBP') return 'webp';
  return null;
}

export async function createAnnoncesApi({ dataDir, secret, adminEmails, askAssistant = null, guidesAssistant = [], comparerPhotos = null }) {
  const store = createStore(dataDir);
  const users = await store.load('users', {});
  const annonces = await store.load('annonces', []);
  const interactions = await store.load('announcement_interactions', {});
  const ratings = await store.load('ratings', {});
  const availability = await store.load('availability', []);
  const visits = await store.load('visits', []);
  const rentals = await store.load('rental_requests', []);
  const photos = await store.load('photos', {});
  const empreintes = await store.load('empreintes_photos', {});
  const arbitrer = creerArbitre(comparerPhotos);
  const photoDir = path.join(dataDir, 'photos');
  const moderation = adminEmails.size > 0;
  const bootId = randomBytes(4).toString('hex');
  let version = 0;

  // Anciennes interactions : les likes pouvaient être de simples identifiants.
  for (const state of Object.values(interactions)) {
    state.likes = (state.likes || []).map((like) => (typeof like === 'string' ? { userId: like, author: 'Utilisateur' } : like));
    state.comments = state.comments || [];
  }

  const changed = (...names) => { version++; return Promise.all(names.map((name) => store.save(name))); };
  const roleOf = (user) => (adminEmails.has(user.email) ? 'administrateur' : user.role);
  const displayName = (userId) => {
    const user = users[userId];
    return user ? `${user.prenom} ${user.nom}`.trim() || 'Utilisateur' : 'Utilisateur';
  };
  const publicUser = (user) => ({ id: user.id, email: user.email, prenom: user.prenom, nom: user.nom, telephone: user.telephone || '', role: roleOf(user) });
  const sessionToken = (user) => signToken({ typ: 'session', sub: user.id, iat: Date.now(), exp: Date.now() + 30 * DAY }, secret);
  const isAdmin = (me) => me.role === 'administrateur';
  const accountStatus = (user) => (adminEmails.has(user.email) ? 'approved' : user.accountStatus ?? 'approved');
  /** Refuse l'accès à un compte bloqué ou en attente de validation. */
  function ensureActive(user) {
    const status = accountStatus(user);
    if (status === 'blocked') fail(403, 'account_blocked', 'Ce compte est bloqué. Contactez l’administrateur.');
    if (status !== 'approved') fail(403, 'account_pending', 'Votre compte attend la validation de l’administrateur.');
  }
  const adminView = (user) => ({ ...publicUser(user), accountStatus: accountStatus(user), createdAt: user.createdAt ?? null });
  const ownerIsAdmin = (annonce) => adminEmails.has(users[annonce.proprietaireId]?.email);
  /** Statut d'une annonce dont la programmation arrive à échéance ou est annulée. */
  const statutApresProgrammation = (annonce) => (moderation && !ownerIsAdmin(annonce) ? 'enAttente' : 'publiee');

  /**
   * Date de publication programmée envoyée par l'application (ISO 8601).
   * undefined : champ absent (pas de changement) ; null : publication immédiate.
   * Sinon : date strictement future (horloge du serveur), un an maximum,
   * normalisée à la seconde en UTC.
   */
  function parsePublication(value) {
    if (value === undefined || value === null) return value;
    const time = typeof value === 'string' ? Date.parse(value) : NaN;
    if (!Number.isFinite(time)) fail(400, 'invalid_field', 'Date de publication invalide.');
    if (time <= Date.now()) fail(400, 'date_passee', 'La date de publication est déjà passée : choisissez une date future.');
    if (time > Date.now() + MAX_PROGRAMMATION) fail(400, 'invalid_field', 'Programmation limitée à un an.');
    return new Date(Math.floor(time / 1000) * 1000).toISOString();
  }

  /**
   * Publie les annonces programmées arrivées à échéance. Appelée avant chaque
   * requête : l'annonce devient visible pour tous dès l'heure prévue, même si
   * le téléphone de son auteur est éteint.
   */
  async function publierEchues() {
    const now = Date.now();
    let count = 0;
    for (const annonce of annonces) {
      if (annonce.statut !== 'programmee' || !annonce.datePublication || Date.parse(annonce.datePublication) > now) continue;
      annonce.statut = statutApresProgrammation(annonce);
      annonce.updatedAt = new Date().toISOString();
      count++;
    }
    if (count) await changed('annonces');
  }
  const canSee = (annonce, me) => annonce.statut === 'publiee' || annonce.proprietaireId === me.id || isAdmin(me);
  const findAnnonce = (id, me) => {
    const annonce = annonces.find((item) => item.id === id);
    if (!annonce || !canSee(annonce, me)) fail(404, 'not_found', 'Annonce introuvable.');
    return annonce;
  };
  const interactionsOf = (id) => interactions[id] || { likes: [], comments: [] };

  /** Le titre et l'image de l'autre annonce ne sont montrés que si elle est publique. */
  function correspondancePublique(c) {
    const visible = annonces.find((a) => a.id === c.annonceCibleId)?.statut === 'publiee';
    return { niveau: c.niveau, raison: c.raison, annonceCibleTitre: visible ? c.annonceCibleTitre : null, photoCible: visible ? c.photoCible : null };
  }

  function view(annonce, me) {
    const state = interactionsOf(annonce.id);
    const notes = Object.values(ratings[annonce.id] || {}).map((rating) => rating.note);
    return {
      ...annonce,
      proprietaireNom: displayName(annonce.proprietaireId),
      likes: state.likes.length,
      aimeParMoi: state.likes.some((like) => like.userId === me.id),
      nbCommentaires: state.comments.length,
      noteMoyenne: notes.length ? Math.round((notes.reduce((a, b) => a + b, 0) / notes.length) * 10) / 10 : 0,
      nbAvis: notes.length,
      maNote: ratings[annonce.id]?.[me.id]?.note ?? null,
    };
  }

  function authenticate(req) {
    const header = req.headers.authorization || '';
    const payload = header.startsWith('Bearer ') ? verifyToken(header.slice(7), secret, 'session') : null;
    const user = payload ? users[payload.sub] : null;
    // Une réinitialisation du mot de passe ferme les sessions ouvertes avant elle.
    if (!user || (user.passwordResetAt && (payload.iat ?? 0) < user.passwordResetAt)) fail(401, 'unauthorized', 'Session expirée : reconnectez-vous.');
    ensureActive(user);
    return { ...user, role: roleOf(user) };
  }

  function validateFacs(value) {
    if (value === undefined || value === null) return [];
    if (!Array.isArray(value) || value.length > 20) fail(400, 'invalid_field', 'Liste de facs invalide.');
    return value.map((fac) => ({
      nom: text(fac?.nom, 1, 160, 'Le nom de la fac'),
      lat: number(fac?.lat, -90, 90, 'La latitude de la fac'),
      lng: number(fac?.lng, -180, 180, 'La longitude de la fac'),
    }));
  }

  function validateAnnonce(body, me, existing) {
    const categorie = CATEGORIES.includes(body.categorie) ? body.categorie : fail(400, 'invalid_field', 'Catégorie invalide.');
    const photoList = Array.isArray(body.photos) ? body.photos : [];
    if (photoList.length > 6) fail(400, 'invalid_field', '6 photos maximum.');
    for (const photo of photoList) {
      const match = typeof photo === 'string' ? photo.match(PHOTO_PATH) : null;
      const allowed = match && (photos[match[1]]?.ownerId === me.id || existing?.photos.includes(photo));
      if (!allowed) fail(400, 'invalid_photo', 'Photo invalide : ajoutez-la de nouveau.');
    }
    const result = {
      categorie,
      titre: text(body.titre, 3, 120, 'Le titre'),
      description: text(body.description, 1, 4000, 'La description'),
      photos: [...new Set(photoList)],
      autoriserCommentaires: body.autoriserCommentaires !== false,
      typeLocation: '', loyer: 0, surface: 0, chambres: 0, etage: null, ville: '', quartier: '', adresse: '', lat: null, lng: null, facsProches: [],
    };
    if (categorie === 'Logement') {
      if (!TYPES_LOGEMENT.includes(body.typeLocation)) fail(400, 'invalid_field', 'Type de logement invalide.');
      // Position facultative, mais toujours complète : latitude et longitude ensemble.
      const positionFournie = (body.lat ?? body.lng ?? null) !== null;
      Object.assign(result, {
        typeLocation: body.typeLocation,
        loyer: number(body.loyer, 1, 100000, 'Le loyer'),
        surface: number(body.surface, 1, 2000, 'La surface'),
        chambres: number(body.chambres, 0, 20, 'Le nombre de chambres', true),
        etage: body.etage === null || body.etage === undefined ? null : number(body.etage, -5, 200, 'L’étage', true),
        ville: text(body.ville, 1, 80, 'La ville'),
        quartier: text(body.quartier, 0, 80, 'Le quartier'),
        adresse: text(body.adresse, 3, 200, 'L’adresse'),
        lat: positionFournie ? number(body.lat, -90, 90, 'La latitude') : null,
        lng: positionFournie ? number(body.lng, -180, 180, 'La longitude') : null,
        facsProches: positionFournie ? validateFacs(body.facsProches) : [],
      });
    }
    return result;
  }

  async function deletePhotos(list) {
    for (const photo of list) {
      const match = photo.match(PHOTO_PATH);
      if (!match) continue;
      delete photos[match[1]];
      delete empreintes[match[1]];
      try { await unlink(path.join(photoDir, match[1])); } catch { /* déjà supprimée */ }
    }
    await store.save('empreintes_photos');
  }

  // ---------- Fiabilité des annonces : photos déjà publiées ----------
  const nomPhoto = (chemin) => chemin.match(PHOTO_PATH)?.[1];
  const mimeImage = (buffer) => ({ jpg: 'image/jpeg', png: 'image/png', webp: 'image/webp' }[sniffImage(buffer)] ?? 'image/jpeg');
  const imagePourIa = (buffer) => ({ buffer, mime: mimeImage(buffer) });

  /** Photos des annonces des autres comptes (celles des messages n'en font jamais partie). */
  function candidatsPour(proprietaireId) {
    const liste = [];
    for (const annonce of annonces) {
      if (annonce.proprietaireId === proprietaireId) continue;
      for (const photo of annonce.photos) {
        const empreinte = empreintes[nomPhoto(photo)];
        if (empreinte) liste.push({ photo, annonce, empreinte });
      }
    }
    return liste;
  }

  async function chercherCorrespondance(buffer, proprietaireId) {
    const proches = chercherProches(await analyserImage(buffer), candidatsPour(proprietaireId));
    if (!proches.length) return null;
    const resultat = (niveau, cible, raison = '') => ({
      niveau, raison, photoCible: cible.photo, annonceCibleId: cible.annonce.id, annonceCibleTitre: cible.annonce.titre, distance: cible.distance,
    });
    const meilleur = proches[0];
    if (meilleur.exact || meilleur.distance <= SEUIL_CERTAIN) return resultat('certaine', meilleur);
    // Sans avis de l'IA, une simple ressemblance ne suffit pas à refuser.
    for (const proche of proches.slice(0, 2)) {
      let verdict = null;
      try { verdict = await arbitrer(imagePourIa(buffer), imagePourIa(await readFile(path.join(photoDir, nomPhoto(proche.photo))))); } catch { /* fichier absent */ }
      if (verdict && estConfirme(verdict)) return resultat('confirmee_ia', proche, verdict.raison);
    }
    return null;
  }

  /** Refuse la publication si une photo de [liste] est déjà utilisée par un autre compte. */
  async function refuserPhotoDejaPubliee(liste, proprietaireId) {
    for (const photo of liste) {
      let buffer;
      try { buffer = await readFile(path.join(photoDir, nomPhoto(photo))); } catch { continue; }
      if (!await chercherCorrespondance(buffer, proprietaireId)) continue;
      await deletePhotos(liste.filter((p) => !annonces.some((a) => a.photos.includes(p))));
      await store.save('photos');
      fail(409, 'photo_deja_publiee', 'Cette photo est déjà utilisée dans une autre annonce : changez-la pour publier.');
    }
  }

  // Empreintes des photos déjà en ligne avant l'arrivée du détecteur.
  let empreintesAjoutees = 0;
  for (const nom of annonces.flatMap((annonce) => annonce.photos).map(nomPhoto).filter((nom) => nom && !empreintes[nom])) {
    try {
      const { sha256, phash } = await analyserImage(await readFile(path.join(photoDir, nom)));
      empreintes[nom] = { sha256, phash };
      empreintesAjoutees++;
    } catch { /* fichier absent */ }
  }
  if (empreintesAjoutees) await store.save('empreintes_photos');

  function freeSlots(ownerId) {
    const now = localNow();
    const horizon = addDays(now.slice(0, 10), 60);
    const booked = visits.filter((visit) => visit.ownerId === ownerId && visit.status === 'confirmed');
    const slots = []; const seen = new Set();
    for (const item of availability.filter((a) => a.ownerId === ownerId && a.active)) {
      for (let day = item.startDate; day <= item.endDate && day <= horizon; day = addDays(day, 1)) {
        if ((item.excludedDates || []).includes(day)) continue;
        const end = minutes(item.endTime);
        for (let m = minutes(item.startTime); m + item.durationMinutes <= end; m += item.durationMinutes + item.breakMinutes) {
          const startAt = `${day}T${clock(m)}`; const endAt = `${day}T${clock(m + item.durationMinutes)}`;
          if (startAt <= now || seen.has(startAt)) continue;
          if (booked.some((visit) => visit.startAt < endAt && startAt < visit.endAt)) continue;
          seen.add(startAt);
          slots.push({ availabilityId: item.id, startAt, endAt });
        }
      }
    }
    return slots.sort((a, b) => a.startAt.localeCompare(b.startAt)).slice(0, 300);
  }

  const housingView = (item) => {
    const annonce = annonces.find((a) => a.id === item.propertyId);
    // L'adresse complète n'est communiquée qu'une fois la location acceptée.
    const logementAdresse = item.status === 'accepted' && annonce
      ? [annonce.adresse, annonce.quartier, annonce.ville].filter(Boolean).join(', ')
      : undefined;
    return { ...item, annonceTitre: annonce?.titre ?? 'Annonce supprimée', clientNom: displayName(item.clientId), proprietaireNom: displayName(item.ownerId), logementAdresse };
  };
  const publishedHousing = (id, me) => {
    const annonce = findAnnonce(id, me);
    if (annonce.categorie !== 'Logement' || annonce.statut !== 'publiee') fail(409, 'not_available', 'Ce logement n’est pas disponible.');
    if (annonce.proprietaireId === me.id) fail(403, 'own_annonce', 'Vous êtes le propriétaire de cette annonce.');
    return annonce;
  };

  const partage = {};
  const routesAssistant = await createAssistantRoutes({ store, users, fail, text, newId, ask: askAssistant, guides: guidesAssistant, partage });
  const routesMessagerie = await createMessagerieRoutes({ store, users, annonces, visits, rentals, photos, photoPath: PHOTO_PATH, fail, text, newId, displayName, partage });

  /** Données du serveur recopiées dans SQLite, limitées à ce que ce compte a le droit de voir. */
  function lireServeur(me) {
    const lesMiennes = (ligne) => ligne.ownerId === me.id || ligne.clientId === me.id;
    const visibles = annonces.filter((a) => canSee(a, me));
    const conversations = partage.messagerie.conversations.filter((c) => c.locataireId === me.id || c.proprietaireId === me.id);
    return {
      visit_availability: availability.filter((a) => a.ownerId === me.id),
      visits: visits.filter(lesMiennes),
      rental_requests: rentals.filter(lesMiennes),
      annonce_likes: visibles.flatMap((a) => interactionsOf(a.id).likes.map((l) => ({ ...l, annonceId: a.id }))),
      annonce_commentaires: visibles.flatMap((a) => interactionsOf(a.id).comments.map((c) => ({ ...c, annonceId: a.id }))),
      annonce_avis: visibles.flatMap((a) => Object.entries(ratings[a.id] || {}).map(([userId, r]) => ({ ...r, userId, annonceId: a.id }))),
      messagerie_conversations: conversations,
      messagerie_messages: conversations.flatMap((c) => (partage.messagerie.messages[c.id] || []).map((m) => ({ ...m, conversationId: c.id }))),
      assistant_conversations: partage.assistant.filter((c) => c.userId === me.id).map((c) => ({ id: c.id, userId: c.userId, updatedAt: c.updatedAt ?? c.createdAt ?? '', donnees: JSON.stringify(c) })),
    };
  }
  const routesMiroir = await createMiroirRoutes({ store, fail, lireServeur });

  const routes = [
    ...routesAssistant,
    ...routesMessagerie,
    ...routesMiroir,
    // ---------- Comptes ----------
    ['POST', /^\/auth\/register$/, false, async ({ body }) => {
      const claim = verifyToken(body.verificationToken, secret, 'email');
      if (!claim) fail(400, 'invalid_verification', 'Vérification e-mail expirée : demandez un nouveau code.');
      if (typeof body.id !== 'string' || !ID.test(body.id)) fail(400, 'invalid_field', 'Identifiant de compte invalide.');
      const password = typeof body.password === 'string' && body.password.length >= 8 && body.password.length <= 200
        ? body.password : fail(400, 'invalid_field', 'Mot de passe : 8 caractères minimum.');
      const role = ROLES_PUBLICS.includes(body.role) ? body.role : 'locataire';
      const existingByEmail = Object.values(users).find((user) => user.email === claim.email);
      if (existingByEmail && existingByEmail.id !== body.id) fail(409, 'email_taken', 'Cette adresse e-mail est déjà liée à un autre compte.');
      if (!existingByEmail && users[body.id]) fail(409, 'id_taken', 'Identifiant de compte déjà utilisé.');
      // Même compte (même id, e-mail prouvé par le code) : mise à jour du mot de passe.
      const user = existingByEmail || { id: body.id, email: claim.email, createdAt: new Date().toISOString(), role };
      user.prenom = text(body.prenom, 1, 80, 'Le prénom');
      user.nom = text(body.nom, 0, 80, 'Le nom');
      user.passwordHash = await hashPassword(password);
      users[user.id] = user;
      await changed('users');
      return [existingByEmail ? 200 : 201, { token: sessionToken(user), user: publicUser(user) }];
    }],
    ['POST', /^\/auth\/login$/, false, async ({ body }) => {
      const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
      const user = Object.values(users).find((item) => item.email === email);
      const ok = user && typeof body.password === 'string' && await checkPassword(body.password, user.passwordHash);
      if (!ok) fail(401, 'invalid_credentials', 'Identifiants incorrects sur le serveur.');
      ensureActive(user);
      return [200, { token: sessionToken(user), user: publicUser(user) }];
    }],
    // Mot de passe oublié : le jeton prouve que le code reçu par e-mail a été saisi.
    ['POST', /^\/auth\/password-reset$/, false, async ({ body }) => {
      const claim = verifyToken(body.verificationToken, secret, 'email');
      if (!claim) fail(400, 'invalid_verification', 'Vérification e-mail expirée : demandez un nouveau code.');
      const password = typeof body.password === 'string' && body.password.length >= 8 && body.password.length <= 200
        ? body.password : fail(400, 'invalid_field', 'Mot de passe : 8 caractères minimum.');
      const user = Object.values(users).find((item) => item.email === claim.email);
      if (!user) fail(404, 'unknown_account', 'Aucun compte serveur pour cette adresse.');
      user.passwordHash = await hashPassword(password);
      user.passwordResetAt = Date.now();
      await changed('users');
      return [200, { updated: true }];
    }],
    // ---------- Administration des comptes ----------
    ['GET', /^\/admin\/users$/, true, async ({ me }) => {
      if (!isAdmin(me)) fail(403, 'forbidden', 'Réservé aux administrateurs.');
      const items = Object.values(users).sort((a, b) => String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? '')));
      return [200, items.map(adminView)];
    }],
    ['POST', /^\/admin\/users\/([A-Za-z0-9_-]{1,100})\/statut$/, true, async ({ me, body, params }) => {
      if (!isAdmin(me)) fail(403, 'forbidden', 'Réservé aux administrateurs.');
      const user = users[params[0]] || fail(404, 'not_found', 'Compte introuvable.');
      if (!['pending', 'approved', 'blocked'].includes(body.statut)) fail(400, 'invalid_field', 'Statut invalide.');
      if (adminEmails.has(user.email)) fail(409, 'admin_account', 'Le statut d’un administrateur ne peut pas être modifié.');
      user.accountStatus = body.statut;
      await changed('users');
      return [200, adminView(user)];
    }],
    ['GET', /^\/me$/, true, async ({ me }) => [200, publicUser(me)]],
    // Changement de mot de passe : l'ancien mot de passe est exigé.
    ['PUT', /^\/me\/password$/, true, async ({ me, body }) => {
      const user = users[me.id];
      const ok = typeof body.ancien === 'string' && await checkPassword(body.ancien, user.passwordHash);
      if (!ok) fail(403, 'invalid_credentials', 'Mot de passe actuel incorrect sur le serveur.');
      const nouveau = typeof body.nouveau === 'string' && body.nouveau.length >= 8 && body.nouveau.length <= 200
        ? body.nouveau : fail(400, 'invalid_field', 'Mot de passe : 8 caractères minimum.');
      user.passwordHash = await hashPassword(nouveau);
      await changed('users');
      return [200, { updated: true }];
    }],
    ['PUT', /^\/me$/, true, async ({ me, body }) => {
      const user = users[me.id];
      user.prenom = text(body.prenom, 1, 80, 'Le prénom');
      user.nom = text(body.nom, 0, 80, 'Le nom');
      await changed('users');
      return [200, publicUser(user)];
    }],

    // ---------- Photos ----------
    ['POST', /^\/photos$/, true, async ({ me, req }) => {
      const buffer = await readBody(req, 6 * 1024 * 1024);
      const ext = sniffImage(buffer) || fail(415, 'unsupported_photo', 'Format photo non supporté (JPEG, PNG ou WebP).');
      const name = `${randomBytes(16).toString('hex')}.${ext}`;
      await mkdir(photoDir, { recursive: true });
      await writeFile(path.join(photoDir, name), buffer);
      photos[name] = { ownerId: me.id, createdAt: new Date().toISOString() };
      const { sha256, phash } = await analyserImage(buffer);
      empreintes[name] = { sha256, phash };
      await Promise.all([store.save('photos'), store.save('empreintes_photos')]);
      return [201, { path: `/photos/${name}` }];
    }],
    // Vérification dès l'ajout dans le formulaire ; rien n'est conservé.
    ['POST', /^\/photos\/verifier$/, true, async ({ me, req }) => {
      const buffer = await readBody(req, 6 * 1024 * 1024);
      if (!sniffImage(buffer)) fail(415, 'unsupported_photo', 'Format photo non supporté (JPEG, PNG ou WebP).');
      const correspondance = await chercherCorrespondance(buffer, me.id);
      return [200, { correspondance: correspondance ? correspondancePublique(correspondance) : null }];
    }],

    // ---------- Annonces ----------
    ['GET', /^\/annonces$/, true, async ({ me, req, res }) => {
      const etag = `"${bootId}-${version}-${me.id}"`;
      if (req.headers['if-none-match'] === etag) { respond(res, 304, undefined, { etag }); return null; }
      const ordre = (a) => (a.statut === 'publiee' && a.datePublication ? a.datePublication : a.createdAt);
      const items = annonces.filter((a) => canSee(a, me))
        .sort((a, b) => ordre(b).localeCompare(ordre(a))).map((a) => view(a, me));
      return [200, { me: { id: me.id, role: me.role, moderation }, items }, { etag }];
    }],
    ['POST', /^\/annonces$/, true, async ({ me, body }) => {
      // Envoi rejoué depuis la file hors ligne : l'annonce n'est pas créée deux fois.
      const dejaCreee = annonces.find((a) => a.id === body.legacyId && a.proprietaireId === me.id);
      if (dejaCreee) return [200, view(dejaCreee, me)];
      const data = validateAnnonce(body, me, null);
      const datePublication = parsePublication(body.datePublication) ?? null;
      await refuserPhotoDejaPubliee(data.photos, me.id);
      const legacy = typeof body.legacyId === 'string' && ID.test(body.legacyId) && !annonces.some((a) => a.id === body.legacyId);
      const now = new Date().toISOString();
      const immediate = !moderation || isAdmin(me) ? 'publiee' : 'enAttente';
      const annonce = {
        id: legacy ? body.legacyId : newId(), ...data, proprietaireId: me.id,
        statut: datePublication ? 'programmee' : immediate, datePublication,
        motifModeration: '', createdAt: now, updatedAt: now,
      };
      annonces.push(annonce);
      await changed('annonces');
      return [201, view(annonce, me)];
    }],
    ['PUT', /^\/annonces\/([A-Za-z0-9_-]{1,100})$/, true, async ({ me, body, params }) => {
      const annonce = findAnnonce(params[0], me);
      if (annonce.proprietaireId !== me.id && !isAdmin(me)) fail(403, 'forbidden', 'Seul le propriétaire peut modifier cette annonce.');
      const data = validateAnnonce(body, me, annonce);
      const datePublication = annonce.proprietaireId === me.id ? parsePublication(body.datePublication) : undefined;
      const removed = annonce.photos.filter((photo) => !data.photos.includes(photo));
      await refuserPhotoDejaPubliee(data.photos.filter((photo) => !annonce.photos.includes(photo)), annonce.proprietaireId);
      Object.assign(annonce, data, { updatedAt: new Date().toISOString() });
      if (moderation && !isAdmin(me) && !['archivee', 'programmee'].includes(annonce.statut)) { annonce.statut = 'enAttente'; annonce.motifModeration = ''; }
      if (datePublication) {
        Object.assign(annonce, { statut: 'programmee', datePublication, motifModeration: '' });
      } else if (datePublication === null && annonce.statut === 'programmee') {
        // Programmation retirée dans le formulaire : publication immédiate (ou validation).
        Object.assign(annonce, { statut: statutApresProgrammation(annonce), datePublication: null });
      }
      await deletePhotos(removed);
      await changed('annonces', 'photos');
      return [200, view(annonce, me)];
    }],
    ['DELETE', /^\/annonces\/([A-Za-z0-9_-]{1,100})$/, true, async ({ me, params }) => {
      const annonce = findAnnonce(params[0], me);
      if (annonce.proprietaireId !== me.id && !isAdmin(me)) fail(403, 'forbidden', 'Seul le propriétaire peut supprimer cette annonce.');
      annonces.splice(annonces.indexOf(annonce), 1);
      delete interactions[annonce.id];
      delete ratings[annonce.id];
      const now = new Date().toISOString();
      for (const visit of visits) if (visit.propertyId === annonce.id && visit.status === 'confirmed') Object.assign(visit, { status: 'cancelled', updatedAt: now });
      for (const request of rentals) if (request.propertyId === annonce.id && request.status === 'pending') Object.assign(request, { status: 'cancelled', updatedAt: now });
      await deletePhotos(annonce.photos);
      await changed('annonces', 'announcement_interactions', 'ratings', 'visits', 'rental_requests', 'photos');
      return [200, { deleted: true }];
    }],
    ['POST', /^\/annonces\/([A-Za-z0-9_-]{1,100})\/statut$/, true, async ({ me, body, params }) => {
      const annonce = findAnnonce(params[0], me);
      const statut = STATUTS.includes(body.statut) ? body.statut : fail(400, 'invalid_field', 'Statut invalide.');
      if (isAdmin(me)) {
        annonce.motifModeration = statut === 'archivee' ? text(body.motif ?? '', 0, 300, 'Le motif') : '';
      } else if (annonce.proprietaireId === me.id) {
        // Sans modération, l'auteur publie lui-même une annonce restée « en attente ».
        const allowed = statut === 'archivee'
          || ((annonce.statut === 'archivee' || (!moderation && annonce.statut === 'enAttente')) && statut === (moderation ? 'enAttente' : 'publiee'));
        if (!allowed) fail(403, 'forbidden', 'Seul un administrateur peut publier une annonce.');
        annonce.motifModeration = '';
      } else fail(403, 'forbidden', 'Action non autorisée.');
      if (annonce.statut === 'programmee') annonce.datePublication = null;
      Object.assign(annonce, { statut, updatedAt: new Date().toISOString() });
      await changed('annonces');
      return [200, view(annonce, me)];
    }],
    // Programmer, reprogrammer ou annuler la publication (auteur uniquement).
    // { datePublication: ISO } → « programmee » ; { datePublication: null, publierMaintenant }
    // → publiee (ou enAttente avec modération) si publierMaintenant, sinon enAttente.
    ['POST', /^\/annonces\/([A-Za-z0-9_-]{1,100})\/programmation$/, true, async ({ me, body, params }) => {
      const annonce = findAnnonce(params[0], me);
      if (annonce.proprietaireId !== me.id) fail(403, 'forbidden', 'Seul l’auteur peut programmer cette annonce.');
      if (!('datePublication' in body)) fail(400, 'invalid_field', 'Date de publication manquante.');
      const datePublication = parsePublication(body.datePublication);
      if (datePublication) {
        Object.assign(annonce, { statut: 'programmee', datePublication, motifModeration: '' });
      } else {
        if (annonce.statut !== 'programmee') fail(409, 'not_scheduled', 'Cette annonce n’est pas programmée.');
        const statut = body.publierMaintenant === false ? 'enAttente' : statutApresProgrammation(annonce);
        Object.assign(annonce, { statut, datePublication: null });
      }
      annonce.updatedAt = new Date().toISOString();
      await changed('annonces');
      return [200, view(annonce, me)];
    }],
    ['POST', /^\/annonces\/([A-Za-z0-9_-]{1,100})\/avis$/, true, async ({ me, body, params }) => {
      const annonce = findAnnonce(params[0], me);
      if (annonce.statut !== 'publiee') fail(409, 'not_published', 'Annonce non publiée.');
      if (annonce.proprietaireId === me.id) fail(403, 'own_annonce', 'Vous ne pouvez pas noter votre propre annonce.');
      const note = number(body.note, 1, 5, 'La note', true);
      ratings[annonce.id] = ratings[annonce.id] || {};
      ratings[annonce.id][me.id] = { note, author: displayName(me.id), createdAt: new Date().toISOString() };
      await changed('ratings');
      return [200, view(annonce, me)];
    }],
    ['GET', /^\/annonces\/([A-Za-z0-9_-]{1,100})\/interactions$/, true, async ({ me, params }) => {
      findAnnonce(params[0], me);
      return [200, interactionsOf(params[0])];
    }],
    ['POST', /^\/annonces\/([A-Za-z0-9_-]{1,100})\/interactions$/, true, async ({ me, body, params }) => {
      const annonce = findAnnonce(params[0], me);
      if (annonce.statut !== 'publiee') fail(409, 'not_published', 'Annonce non publiée.');
      const state = interactions[annonce.id] || { likes: [], comments: [] };
      const author = displayName(me.id);
      const createdAt = new Date().toISOString();
      if (body.action === 'like' && typeof body.liked === 'boolean') {
        state.likes = state.likes.filter((like) => like.userId !== me.id);
        if (body.liked) state.likes.push({ userId: me.id, author, createdAt });
      } else if (body.action === 'comment') {
        if (!annonce.autoriserCommentaires) fail(403, 'comments_disabled', 'Les commentaires sont désactivés.');
        state.comments.push({ userId: me.id, author, text: text(body.text, 1, 2000, 'Le commentaire'), createdAt });
        state.comments = state.comments.slice(-500);
      } else fail(400, 'invalid_interaction', 'Action invalide.');
      interactions[annonce.id] = state;
      await changed('announcement_interactions');
      return [200, state];
    }],
    ['GET', /^\/annonces\/([A-Za-z0-9_-]{1,100})\/creneaux$/, true, async ({ me, params }) => {
      const annonce = publishedHousing(params[0], me);
      return [200, freeSlots(annonce.proprietaireId)];
    }],

    // ---------- Disponibilités de visite ----------
    ['GET', /^\/disponibilites$/, true, async ({ me }) => [200, availability.filter((a) => a.ownerId === me.id && a.active)]],
    ['POST', /^\/disponibilites$/, true, async ({ me, body }) => {
      if (!isDate(body.startDate) || !isDate(body.endDate)) fail(400, 'invalid_field', 'Dates au format AAAA-MM-JJ attendues.');
      if (body.endDate < body.startDate) fail(400, 'invalid_field', 'La date de fin doit suivre la date de début.');
      if (body.endDate < localNow().slice(0, 10)) fail(400, 'invalid_field', 'Ces dates sont déjà passées.');
      if (daysBetween(body.startDate, body.endDate) > 90) fail(400, 'invalid_field', '90 jours maximum par plage.');
      if (!isTime(body.startTime) || !isTime(body.endTime)) fail(400, 'invalid_field', 'Heures au format HH:MM attendues.');
      const durationMinutes = number(body.durationMinutes, 10, 240, 'La durée de visite', true);
      const breakMinutes = number(body.breakMinutes ?? 0, 0, 120, 'La pause', true);
      if (minutes(body.startTime) + durationMinutes > minutes(body.endTime)) fail(400, 'invalid_field', 'La plage horaire est trop courte pour une visite.');
      const excludedDates = body.excludedDates ?? [];
      if (!Array.isArray(excludedDates) || excludedDates.length > 100 || excludedDates.some((date) => !isDate(date) || date < body.startDate || date > body.endDate)) {
        fail(400, 'invalid_field', 'Liste de jours exclus invalide.');
      }
      const item = {
        id: newId(), ownerId: me.id, startDate: body.startDate, endDate: body.endDate, startTime: body.startTime,
        endTime: body.endTime, durationMinutes, breakMinutes, excludedDates: [...new Set(excludedDates)], active: true, createdAt: new Date().toISOString(),
      };
      availability.push(item);
      await changed('availability');
      return [201, item];
    }],
    ['DELETE', /^\/disponibilites\/([A-Za-z0-9_-]{1,100})$/, true, async ({ me, params }) => {
      const item = availability.find((a) => a.id === params[0] && a.ownerId === me.id) || fail(404, 'not_found', 'Disponibilité introuvable.');
      item.active = false;
      await changed('availability');
      return [200, { deleted: true }];
    }],

    // ---------- Visites ----------
    ['GET', /^\/visites$/, true, async ({ me }) => {
      const sorted = [...visits].sort((a, b) => b.startAt.localeCompare(a.startAt));
      return [200, {
        recues: sorted.filter((v) => v.ownerId === me.id).map(housingView),
        envoyees: sorted.filter((v) => v.clientId === me.id).map(housingView),
      }];
    }],
    ['POST', /^\/visites$/, true, async ({ me, body }) => {
      const annonce = publishedHousing(body.annonceId, me);
      const slot = freeSlots(annonce.proprietaireId).find((s) => s.startAt === body.startAt);
      if (!slot) fail(409, 'slot_unavailable', 'Ce créneau vient d’être réservé ou n’existe plus.');
      const now = localNow();
      if (visits.some((v) => v.clientId === me.id && v.propertyId === annonce.id && v.status === 'confirmed' && v.endAt > now)) {
        fail(409, 'already_booked', 'Vous avez déjà une visite prévue pour ce logement.');
      }
      const visit = {
        id: newId(), availabilityId: slot.availabilityId, ownerId: annonce.proprietaireId, clientId: me.id, propertyId: annonce.id,
        startAt: slot.startAt, endAt: slot.endAt, status: 'confirmed', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
      };
      visits.push(visit);
      await changed('visits');
      return [201, housingView(visit)];
    }],
    ['POST', /^\/visites\/([A-Za-z0-9_-]{1,100})\/statut$/, true, async ({ me, body, params }) => {
      const visit = visits.find((v) => v.id === params[0] && (v.clientId === me.id || v.ownerId === me.id)) || fail(404, 'not_found', 'Visite introuvable.');
      if (body.statut !== 'cancelled' || visit.status !== 'confirmed') fail(409, 'invalid_transition', 'Cette visite ne peut plus être annulée.');
      Object.assign(visit, { status: 'cancelled', cancelledBy: me.id, updatedAt: new Date().toISOString() });
      await changed('visits');
      return [200, housingView(visit)];
    }],

    // ---------- Demandes de location ----------
    ['GET', /^\/demandes-location$/, true, async ({ me }) => {
      const sorted = [...rentals].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
      return [200, {
        recues: sorted.filter((r) => r.ownerId === me.id).map(housingView),
        envoyees: sorted.filter((r) => r.clientId === me.id).map(housingView),
      }];
    }],
    ['POST', /^\/demandes-location$/, true, async ({ me, body }) => {
      const annonce = publishedHousing(body.annonceId, me);
      if (!isDate(body.startDate) || !isDate(body.endDate)) fail(400, 'invalid_field', 'Dates au format AAAA-MM-JJ attendues.');
      if (body.startDate < localNow().slice(0, 10)) fail(400, 'invalid_field', 'La date de début est déjà passée.');
      if (body.endDate <= body.startDate) fail(400, 'invalid_field', 'La date de fin doit suivre la date de début.');
      if (!FREQUENCES.includes(body.paymentFrequency) || !MOYENS.includes(body.paymentMethod)) fail(400, 'invalid_field', 'Mode de paiement invalide.');
      if (rentals.some((r) => r.clientId === me.id && r.propertyId === annonce.id && r.status === 'pending')) {
        fail(409, 'already_requested', 'Une demande est déjà en attente pour ce logement.');
      }
      const lastVisit = visits.filter((v) => v.clientId === me.id && v.propertyId === annonce.id && v.status === 'confirmed')
        .sort((a, b) => b.startAt.localeCompare(a.startAt))[0];
      const now = new Date().toISOString();
      const request = {
        id: newId(), ownerId: annonce.proprietaireId, clientId: me.id, propertyId: annonce.id, visitId: lastVisit?.id ?? null,
        monthlyRent: annonce.loyer, propertyType: annonce.typeLocation, startDate: body.startDate, endDate: body.endDate,
        duration: number(body.duration, 1, 60, 'La durée', true), paymentFrequency: body.paymentFrequency,
        paymentMethod: body.paymentMethod, additionalMessage: text(body.additionalMessage ?? '', 0, 1000, 'Le message'),
        status: 'pending', createdAt: now, updatedAt: now,
      };
      rentals.push(request);
      await changed('rental_requests');
      return [201, housingView(request)];
    }],
    ['POST', /^\/demandes-location\/([A-Za-z0-9_-]{1,100})\/statut$/, true, async ({ me, body, params }) => {
      const request = rentals.find((r) => r.id === params[0] && (r.clientId === me.id || r.ownerId === me.id)) || fail(404, 'not_found', 'Demande introuvable.');
      const asOwner = request.ownerId === me.id && ['accepted', 'refused'].includes(body.statut);
      const asClient = request.clientId === me.id && body.statut === 'cancelled';
      if (request.status !== 'pending' || (!asOwner && !asClient)) fail(409, 'invalid_transition', 'Cette demande a déjà été traitée.');
      Object.assign(request, { status: body.statut, updatedAt: new Date().toISOString() });
      await changed('rental_requests');
      return [200, housingView(request)];
    }],

    // ---------- Activité ----------
    ['GET', /^\/activite$/, true, async ({ me }) => {
      const items = [];
      const titleOf = (id) => annonces.find((a) => a.id === id)?.titre ?? 'Annonce supprimée';
      for (const annonce of annonces.filter((a) => a.proprietaireId === me.id)) {
        const state = interactionsOf(annonce.id);
        for (const like of state.likes) if (like.userId !== me.id) items.push({ type: 'like', annonceId: annonce.id, annonceTitre: annonce.titre, auteur: like.author, detail: '', date: like.createdAt ?? null });
        for (const c of state.comments) if (c.userId !== me.id) items.push({ type: 'commentaire', annonceId: annonce.id, annonceTitre: annonce.titre, auteur: c.author, detail: c.text, date: c.createdAt ?? null });
        for (const [userId, r] of Object.entries(ratings[annonce.id] || {})) items.push({ type: 'avis', annonceId: annonce.id, annonceTitre: annonce.titre, auteur: displayName(userId), detail: `${r.note}/5`, date: r.createdAt });
        if (annonce.motifModeration) items.push({ type: 'moderation', annonceId: annonce.id, annonceTitre: annonce.titre, auteur: 'Modération', detail: annonce.motifModeration, date: annonce.updatedAt });
      }
      for (const v of visits.filter((x) => x.ownerId === me.id)) items.push({ type: 'visite', annonceId: v.propertyId, annonceTitre: titleOf(v.propertyId), auteur: displayName(v.clientId), detail: `${v.startAt.replace('T', ' ')}${v.status === 'cancelled' ? ' (annulée)' : ''}`, date: v.updatedAt ?? v.createdAt });
      for (const r of rentals.filter((x) => x.ownerId === me.id)) items.push({ type: 'demande', annonceId: r.propertyId, annonceTitre: titleOf(r.propertyId), auteur: displayName(r.clientId), detail: r.status, date: r.createdAt });
      for (const r of rentals.filter((x) => x.clientId === me.id && x.status !== 'pending')) items.push({ type: 'reponse', annonceId: r.propertyId, annonceTitre: titleOf(r.propertyId), auteur: displayName(r.ownerId), detail: r.status, date: r.updatedAt });
      items.sort((a, b) => String(b.date ?? '').localeCompare(String(a.date ?? '')));
      return [200, items.slice(0, 150)];
    }],
  ];

  async function servePhoto(res, name) {
    const file = path.join(photoDir, name);
    try { await stat(file); } catch { respond(res, 404, { error: 'not_found' }); return; }
    const type = name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    res.writeHead(200, { 'content-type': type, 'cache-control': 'public, max-age=31536000, immutable' });
    createReadStream(file).pipe(res);
  }

  return {
    moderation,
    /** Jeton court prouvant qu'une adresse e-mail vient d'être vérifiée par code. */
    emailToken: (email) => signToken({ typ: 'email', email: email.toLowerCase(), exp: Date.now() + 30 * 60 * 1000 }, secret),
    /** Traite la requête si elle concerne cette API ; retourne false sinon. */
    async handle(req, res) {
      const { pathname } = new URL(req.url, 'http://localhost');
      const photo = req.method === 'GET' && pathname.match(/^\/photos\/([a-f0-9]{32}\.(?:jpg|png|webp))$/);
      if (photo) { await servePhoto(res, photo[1]); return true; }
      for (const [method, pattern, needsAuth, handler] of routes) {
        const match = pathname.match(pattern);
        if (!match) continue;
        if (req.method !== method) continue;
        try {
          await publierEchues();
          const me = needsAuth ? authenticate(req) : null;
          const body = ['POST', 'PUT'].includes(method) && !['/photos', '/photos/verifier'].includes(pathname) ? await readJson(req) : {};
          const result = await handler({ req, res, me, body, params: match.slice(1) });
          if (result) respond(res, result[0], result[1], result[2]);
        } catch (error) {
          if (error instanceof HttpError) respond(res, error.status, { error: error.code, message: error.message });
          else {
            console.error(`API ${method} ${pathname} : ${error instanceof Error ? error.message : 'erreur inconnue'}`);
            respond(res, 500, { error: 'server_error', message: 'Erreur interne du serveur.' });
          }
        }
        return true;
      }
      return false;
    },
  };
}
