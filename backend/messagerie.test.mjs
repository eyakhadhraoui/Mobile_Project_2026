import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';

import { createAnnoncesApi } from './annonces_api.mjs';
import { signToken } from './auth.mjs';

const secret = 'secret-de-test-uniquement';
const compte = (id, prenom) => ({ id, email: `${id}@test.tn`, prenom, nom: 'Test', role: 'locataire', passwordHash: 'x', createdAt: '2026-01-01T00:00:00.000Z' });
const logement = (id, statut = 'publiee') => ({
  id, categorie: 'Logement', titre: `Studio ${id}`, description: 'd', photos: [], autoriserCommentaires: true, typeLocation: 'Studio',
  loyer: 300, surface: 30, chambres: 1, etage: 1, ville: 'Tunis', quartier: '', adresse: 'rue', lat: null, lng: null, facsProches: [],
  proprietaireId: 'sami', statut, datePublication: null, motifModeration: '', createdAt: '2026-01-01T00:00:00.000Z', updatedAt: '2026-01-01T00:00:00.000Z',
});

let dossier, serveur, base;

before(async () => {
  dossier = await mkdtemp(path.join(os.tmpdir(), 'messagerie-'));
  await mkdir(dossier, { recursive: true });
  const ecrire = (nom, valeur) => writeFile(path.join(dossier, `${nom}.json`), JSON.stringify(valeur));
  await ecrire('users', { sami: compte('sami', 'Sami'), yasmine: compte('yasmine', 'Yasmine'), omar: compte('omar', 'Omar'), admin: compte('admin', 'Admin') });
  await ecrire('annonces', [logement('a1'), logement('archivee', 'archivee'), logement('demandee')]);
  await ecrire('rental_requests', [{ id: 'r1', ownerId: 'sami', clientId: 'omar', propertyId: 'demandee', status: 'pending', createdAt: '2026-01-02T00:00:00.000Z' }]);
  const api = await createAnnoncesApi({ dataDir: dossier, secret, adminEmails: new Set(['admin@test.tn']) });
  serveur = http.createServer((req, res) => {
    api.handle(req, res).then((traite) => { if (!traite) { res.writeHead(404); res.end(); } });
  });
  await new Promise((ok) => { serveur.listen(0, '127.0.0.1', ok); });
  base = `http://127.0.0.1:${serveur.address().port}`;
});

after(async () => {
  await new Promise((ok) => { serveur.close(ok); });
  await rm(dossier, { recursive: true, force: true });
});

const jeton = (id) => signToken({ typ: 'session', sub: id, iat: Date.now(), exp: Date.now() + 60_000 }, secret);
async function appel(qui, methode, chemin, corps, entetes = {}) {
  const res = await fetch(`${base}${chemin}`, {
    method: methode,
    headers: { ...(qui ? { authorization: `Bearer ${jeton(qui)}` } : {}), ...(corps ? { 'content-type': 'application/json' } : {}), ...entetes },
    body: corps ? JSON.stringify(corps) : undefined,
  });
  const texte = await res.text();
  return { status: res.status, data: texte ? JSON.parse(texte) : null, etag: res.headers.get('etag') };
}
const ouvrir = async (qui, annonceId, extra = {}) => (await appel(qui, 'POST', '/conversations', { annonceId, ...extra }));
const envoyer = (qui, id, corps) => appel(qui, 'POST', `/conversations/${id}/messages`, corps);

test('une session est obligatoire', async () => {
  assert.equal((await appel(null, 'GET', '/conversations')).status, 401);
});

test('le locataire ouvre une seule conversation par annonce', async () => {
  const premiere = await ouvrir('yasmine', 'a1');
  assert.equal(premiere.status, 201);
  assert.equal(premiere.data.interlocuteurNom, 'Sami Test');
  const seconde = await ouvrir('yasmine', 'a1');
  assert.equal(seconde.status, 200);
  assert.equal(seconde.data.id, premiere.data.id);
});

test('une conversation vide reste hors de la liste', async () => {
  await ouvrir('omar', 'a1');
  assert.equal((await appel('omar', 'GET', '/conversations')).data.length, 0);
});

test('un tiers, même administrateur, ne voit rien', async () => {
  const { data } = await ouvrir('yasmine', 'a1');
  for (const intrus of ['omar', 'admin']) {
    assert.equal((await appel(intrus, 'GET', `/conversations/${data.id}/messages`)).status, 404);
    assert.equal((await envoyer(intrus, data.id, { texte: 'coucou' })).status, 404);
  }
});

test('le propriétaire écrit seulement à qui a demandé une visite ou une location', async () => {
  assert.equal((await ouvrir('sami', 'a1', { locataireId: 'yasmine' })).status, 403);
  assert.equal((await ouvrir('sami', 'demandee', { locataireId: 'yasmine' })).status, 403);
  assert.equal((await ouvrir('sami', 'demandee', { locataireId: 'omar' })).status, 201);
});

test('une annonce archivée ne permet pas de nouveau contact', async () => {
  assert.equal((await ouvrir('yasmine', 'archivee')).status, 409);
});

test('non lus, lecture et ETag', async () => {
  const { data } = await ouvrir('omar', 'demandee');
  await envoyer('omar', data.id, { texte: 'Bonjour', langue: 'fr' });
  const avant = await appel('sami', 'GET', '/conversations');
  const resume = avant.data.find((c) => c.id === data.id);
  assert.equal(resume.nonLus, 1);
  assert.equal(resume.estProprietaire, true);
  assert.equal(resume.dernierMessage.texte, 'Bonjour');
  const lecture = await appel('sami', 'GET', `/conversations/${data.id}/messages`);
  assert.equal(lecture.data.messages.length, 1);
  assert.equal(lecture.data.conversation.nonLus, 0);
  const inchange = await appel('sami', 'GET', `/conversations/${data.id}/messages`, undefined, { 'if-none-match': lecture.etag });
  assert.equal(inchange.status, 304);
  // Ses propres messages ne comptent pas comme non lus.
  assert.equal((await appel('omar', 'GET', '/conversations')).data.find((c) => c.id === data.id).nonLus, 0);
});

test('un envoi rejoué ne crée pas de doublon', async () => {
  const { data } = await ouvrir('yasmine', 'a1');
  const premier = await envoyer('yasmine', data.id, { texte: 'Disponible ?', clientId: 'rejoue-1' });
  const rejoue = await envoyer('yasmine', data.id, { texte: 'Disponible ?', clientId: 'rejoue-1' });
  assert.equal(premier.status, 201);
  assert.equal(rejoue.status, 200);
  assert.equal(rejoue.data.id, premier.data.id);
  const { data: lecture } = await appel('yasmine', 'GET', `/conversations/${data.id}/messages`);
  assert.equal(lecture.messages.filter((m) => m.clientId === 'rejoue-1').length, 1);
});

test('un message vide ou une photo d’autrui sont refusés', async () => {
  const { data } = await ouvrir('yasmine', 'a1');
  assert.equal((await envoyer('yasmine', data.id, { texte: '   ' })).status, 400);
  const inconnue = `/photos/${'a'.repeat(32)}.jpg`;
  assert.equal((await envoyer('yasmine', data.id, { texte: 'x', photos: [inconnue] })).data.error, 'invalid_photo');
  assert.equal((await envoyer('yasmine', data.id, { photos: ['../secret'] })).status, 400);
});

test('un message accepte les photos de son auteur', async () => {
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0]);
  const res = await fetch(`${base}/photos`, { method: 'POST', headers: { authorization: `Bearer ${jeton('yasmine')}` }, body: jpeg });
  const { path: photo } = await res.json();
  const { data } = await ouvrir('yasmine', 'a1');
  const envoi = await envoyer('yasmine', data.id, { photos: [photo] });
  assert.equal(envoi.status, 201);
  assert.deepEqual(envoi.data.photos, [photo]);
  assert.equal(envoi.data.texte, '');
  assert.equal((await envoyer('omar', (await ouvrir('omar', 'demandee')).data.id, { photos: [photo] })).status, 400);
  const liste = (await appel('yasmine', 'GET', '/conversations')).data;
  assert.equal(liste.find((c) => c.id === data.id).dernierMessage.nbPhotos, 1);
});
