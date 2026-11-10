import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';

import { createAnnoncesApi } from './annonces_api.mjs';
import { signToken } from './auth.mjs';

const secret = 'secret-de-test-uniquement';
const compte = (id) => ({ id, email: `${id}@test.tn`, prenom: id, nom: 'T', role: 'locataire', passwordHash: 'x', createdAt: '2026-01-01T00:00:00.000Z' });
let dossier, serveur, base;

before(async () => {
  dossier = await mkdtemp(path.join(os.tmpdir(), 'miroir-'));
  await writeFile(path.join(dossier, 'users.json'), JSON.stringify({ a: compte('a'), b: compte('b'), c: compte('c') }));
  await writeFile(path.join(dossier, 'visits.json'), JSON.stringify([
    { id: 'v1', availabilityId: 'd', ownerId: 'b', clientId: 'a', propertyId: 'p', startAt: 'x', endAt: 'y', status: 'confirmed' },
  ]));
  const api = await createAnnoncesApi({ dataDir: dossier, secret, adminEmails: new Set() });
  serveur = http.createServer((req, res) => { api.handle(req, res).then((traite) => { if (!traite) { res.writeHead(404); res.end(); } }); });
  await new Promise((ok) => { serveur.listen(0, '127.0.0.1', ok); });
  base = `http://127.0.0.1:${serveur.address().port}`;
});

after(async () => {
  await new Promise((ok) => { serveur.close(ok); });
  await rm(dossier, { recursive: true, force: true });
});

async function sync(qui, changements = [], depuis = 0) {
  const res = await fetch(`${base}/miroir/synchroniser`, {
    method: 'POST',
    headers: { authorization: `Bearer ${signToken({ typ: 'session', sub: qui, iat: Date.now(), exp: Date.now() + 60_000 }, secret)}`, 'content-type': 'application/json' },
    body: JSON.stringify({ depuis, changements }),
  });
  return { status: res.status, ...(await res.json()) };
}
const trajet = (id, auteurId, places = 3) => ({ table: 'covoiturage_trajets', cle: [id], ligne: { id, auteurId, places, statut: 'ouvert', depart: 'Tunis' } });
const lignesDe = (r, table) => r.lignes.filter((l) => l.table === table);

test('une session est obligatoire', async () => {
  const res = await fetch(`${base}/miroir/synchroniser`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
  assert.equal(res.status, 401);
});

test('une ligne envoyée est écrite dans le JSON et visible par les autres', async () => {
  const r = await sync('a', [trajet('t1', 'a')]);
  assert.deepEqual(r.refuses, []);
  const fichier = JSON.parse(await readFile(path.join(dossier, 'covoiturage_trajets.json'), 'utf8'));
  assert.equal(Object.values(fichier)[0].ligne.depart, 'Tunis');
  assert.ok(lignesDe(await sync('b'), 'covoiturage_trajets').some((l) => l.cle[0] === 't1'));
});

test('on ne peut pas écrire au nom de quelqu’un d’autre', async () => {
  const r = await sync('b', [trajet('faux', 'a')]);
  assert.deepEqual(r.refuses, [0]);
  assert.equal(lignesDe(await sync('a'), 'covoiturage_trajets').filter((l) => l.cle[0] === 'faux').length, 0);
});

test('un passager ne modifie que les places et le statut', async () => {
  await sync('a', [trajet('t2', 'a', 4)]);
  await sync('b', [{ table: 'covoiturage_reservations', cle: ['r2'], ligne: { id: 'r2', trajetId: 't2', participantId: 'b', statut: 'enAttente' } }]);
  const passager = await sync('b', [{ table: 'covoiturage_trajets', cle: ['t2'], ligne: { id: 't2', auteurId: 'a', places: 3, statut: 'ouvert', depart: 'Pirate' } }]);
  assert.deepEqual(passager.refuses, []);
  const ligne = lignesDe(await sync('c'), 'covoiturage_trajets').find((l) => l.cle[0] === 't2').ligne;
  assert.equal(ligne.places, 3);
  assert.equal(ligne.depart, 'Tunis');
});

test('une réservation n’est visible que du passager et du conducteur', async () => {
  const voit = async (qui) => lignesDe(await sync(qui), 'covoiturage_reservations').some((l) => l.cle[0] === 'r2');
  assert.equal(await voit('a'), true);
  assert.equal(await voit('b'), true);
  assert.equal(await voit('c'), false);
});

test('une demande de maintenance arrive au propriétaire, pas aux autres', async () => {
  const demande = { id: 'd1', userId: 'a', proprietaireId: 'b', title: 'Fuite', statut: 'nouvelle' };
  assert.deepEqual((await sync('a', [
    { table: 'demandes', cle: ['d1'], ligne: demande },
    { table: 'demande_historique', cle: ['d1', '2026', 'nouvelle'], ligne: { demandeId: 'd1', date: '2026', statut: 'nouvelle', auteurId: 'a' } },
  ])).refuses, []);
  const proprietaire = await sync('b');
  assert.equal(lignesDe(proprietaire, 'demandes')[0].ligne.title, 'Fuite');
  assert.equal(lignesDe(proprietaire, 'demande_historique').length, 1);
  const autre = await sync('c');
  assert.equal(lignesDe(autre, 'demandes').length, 0);
  assert.equal(lignesDe(autre, 'demande_historique').length, 0);
});

test('une suppression se propage', async () => {
  await sync('a', [trajet('t3', 'a')]);
  const avant = (await sync('b')).revision;
  await sync('a', [{ table: 'covoiturage_trajets', cle: ['t3'], ligne: null }]);
  const apres = lignesDe(await sync('b', [], avant), 'covoiturage_trajets');
  assert.equal(apres.length, 1);
  assert.equal(apres[0].ligne, null);
});

test('seuls les changements récents sont renvoyés', async () => {
  const { revision } = await sync('a');
  assert.equal((await sync('a', [], revision)).lignes.length, 0);
});

test('les tables sans propriétaire restent propres à chaque compte', async () => {
  const geo = (lat) => ({ table: 'geocodage', cle: ['rue X'], ligne: { adresse: 'rue X', lat } });
  await sync('a', [geo(1)]);
  await sync('b', [geo(2)]);
  assert.equal(lignesDe(await sync('a'), 'geocodage')[0].ligne.lat, 1);
  assert.equal(lignesDe(await sync('b'), 'geocodage')[0].ligne.lat, 2);
  assert.equal(lignesDe(await sync('c'), 'geocodage').length, 0);
});

test('les tables sensibles et les valeurs invalides sont refusées', async () => {
  const r = await sync('a', [
    { table: 'users', cle: ['a'], ligne: { id: 'a', passwordHash: 'x' } },
    { table: 'app_settings', cle: ['apiToken'], ligne: { key: 'apiToken', value: 'x' } },
    { table: '__proto__', cle: ['x'], ligne: {} },
    { table: 'covoiturage_trajets', cle: ['x'], ligne: { id: 'y', auteurId: 'a' } },
    { table: 'covoiturage_trajets', cle: ['z'], ligne: { id: 'z', auteurId: 'a', objet: { a: 1 } } },
    null,
  ]);
  assert.deepEqual(r.refuses.sort(), [0, 1, 2, 3, 4, 5]);
});

test('un envoi trop volumineux est refusé', async () => {
  assert.equal((await sync('a', Array.from({ length: 101 }, (_, i) => trajet(`g${i}`, 'a')))).status, 400);
});

test('les données du serveur sont renvoyées pour SQLite, selon le compte', async () => {
  assert.equal((await sync('a')).serveur.visits.length, 1);
  assert.equal((await sync('b')).serveur.visits.length, 1);
  assert.equal((await sync('c')).serveur.visits.length, 0);
});
