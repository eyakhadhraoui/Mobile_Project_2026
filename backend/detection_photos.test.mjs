import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';

import sharp from 'sharp';

import { createAnnoncesApi } from './annonces_api.mjs';
import { signToken } from './auth.mjs';
import { analyserImage, chercherProches, creerArbitre, distance, estConfirme, SEUIL_CERTAIN, SEUIL_DOUTE } from './detection_photos.mjs';

/** Scène pseudo-aléatoire reproductible : mur, sol et meubles stylisés. */
function scene(graine) {
  let s = graine;
  const r = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
  const c = () => `rgb(${50 + r() * 200 | 0},${50 + r() * 200 | 0},${50 + r() * 200 | 0})`;
  let formes = `<rect width="1200" height="620" fill="${c()}"/><rect y="620" width="1200" height="280" fill="${c()}"/>`;
  for (let i = 0; i < 14; i++) formes += `<rect x="${r() * 1100 | 0}" y="${r() * 800 | 0}" width="${40 + r() * 320 | 0}" height="${40 + r() * 300 | 0}" rx="${r() * 30 | 0}" fill="${c()}"/>`;
  for (let i = 0; i < 8; i++) formes += `<circle cx="${r() * 1200 | 0}" cy="${r() * 900 | 0}" r="${15 + r() * 90 | 0}" fill="${c()}"/>`;
  return sharp(Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="900">${formes}</svg>`)).jpeg({ quality: 92 }).toBuffer();
}
const ecart = (requete, cible) => Math.min(...requete.variantes.map((v) => distance(v, cible.phash)));

const CERTAINES = {
  recompression: (b) => sharp(b).jpeg({ quality: 40 }).toBuffer(),
  redimensionnement: (b) => sharp(b).resize(400).jpeg({ quality: 70 }).toBuffer(),
  miroir: (b) => sharp(b).flop().jpeg().toBuffer(),
  rotation: (b) => sharp(b).rotate(90).jpeg().toBuffer(),
  png: (b) => sharp(b).png().toBuffer(),
  'petit recadrage': (b) => sharp(b).extract({ left: 18, top: 13, width: 1164, height: 874 }).jpeg().toBuffer(),
};

for (const [nom, transformer] of Object.entries(CERTAINES)) {
  test(`${nom} : reconnue avec certitude`, async () => {
    for (const graine of [7919, 15838, 23757, 31676]) {
      const originale = await scene(graine);
      assert.ok(ecart(await analyserImage(await transformer(originale)), await analyserImage(originale)) <= SEUIL_CERTAIN, `graine ${graine}`);
    }
  });
}

test('un recadrage modéré tombe au pire dans la zone douteuse', async () => {
  for (const graine of [7919, 15838, 23757]) {
    const originale = await scene(graine);
    const recadree = await sharp(originale).extract({ left: 48, top: 36, width: 1104, height: 828 }).jpeg().toBuffer();
    assert.ok(ecart(await analyserImage(recadree), await analyserImage(originale)) <= SEUIL_DOUTE);
  }
});

test('des images différentes ne sont pas rapprochées', async () => {
  const images = await Promise.all(Array.from({ length: 10 }, async (_, i) => analyserImage(await scene((i + 1) * 104729))));
  for (let i = 0; i < images.length; i++) {
    for (let j = i + 1; j < images.length; j++) assert.ok(ecart(images[i], images[j]) > SEUIL_DOUTE, `${i}/${j}`);
  }
});

test('une image presque unie n’a pas d’empreinte perceptuelle, mais reste comparée à l’identique', async () => {
  const blanc = await sharp({ create: { width: 200, height: 200, channels: 3, background: '#f4f4f4' } }).jpeg().toBuffer();
  const gris = await sharp({ create: { width: 200, height: 200, channels: 3, background: '#d0d0d0' } }).jpeg().toBuffer();
  const a = await analyserImage(blanc);
  assert.equal(a.phash, null);
  assert.equal(chercherProches(a, [{ empreinte: await analyserImage(gris) }]).length, 0);
  assert.equal(chercherProches(a, [{ empreinte: a }])[0].exact, true);
});

test('un fichier illisible ne fait pas échouer l’analyse', async () => {
  assert.equal((await analyserImage(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2]))).phash, null);
});

test('l’arbitre garde les verdicts, respecte son quota et ne plante pas', async () => {
  let appels = 0;
  const arbitrer = creerArbitre(async () => { appels++; return { meme_image: true, confiance: 0.9, raison: 'x' }; }, { limiteHeure: 2 });
  const a = { buffer: Buffer.from('a') }, b = { buffer: Buffer.from('b') }, c = { buffer: Buffer.from('c') }, d = { buffer: Buffer.from('d') };
  assert.equal((await arbitrer(a, b)).memeImage, true);
  await arbitrer(b, a);
  assert.equal(appels, 1, 'paire déjà jugée');
  await arbitrer(a, c);
  assert.equal(await arbitrer(a, d), null, 'quota atteint');
  assert.equal(await creerArbitre(null)(a, b), null);
  assert.equal(await creerArbitre(async () => { throw new Error('panne'); })(a, b), null);
});

test('confirmation : même image, ou même lieu avec forte confiance', () => {
  assert.ok(estConfirme({ memeImage: true, memeLieu: false, confiance: 0.1 }));
  assert.ok(estConfirme({ memeImage: false, memeLieu: true, confiance: 0.85 }));
  assert.ok(!estConfirme({ memeImage: false, memeLieu: true, confiance: 0.5 }));
  assert.ok(!estConfirme({ memeImage: false, memeLieu: false, confiance: 1 }));
});

// ---------------------------------------------------------------------------
// Parcours complet par l'API, sans appel réel au modèle de vision.
// ---------------------------------------------------------------------------
const secret = 'secret-de-test-uniquement';
const compte = (id) => ({ id, email: `${id}@test.tn`, prenom: id, nom: 'Test', role: 'proprietaire', passwordHash: 'x', createdAt: '2026-01-01T00:00:00.000Z' });
let dossier, serveur, base;
let verdictIa = null;
let appelsIa = 0;

before(async () => {
  dossier = await mkdtemp(path.join(os.tmpdir(), 'detection-'));
  await writeFile(path.join(dossier, 'users.json'), JSON.stringify({ sami: compte('sami'), voleur: compte('voleur'), autre: compte('autre'), admin: compte('admin') }));
  const api = await createAnnoncesApi({
    dataDir: dossier, secret, adminEmails: new Set(['admin@test.tn']),
    comparerPhotos: async () => { appelsIa++; if (verdictIa === 'panne') throw new Error('panne'); return verdictIa; },
  });
  serveur = http.createServer((req, res) => { api.handle(req, res).then((traite) => { if (!traite) { res.writeHead(404); res.end(); } }); });
  await new Promise((ok) => { serveur.listen(0, '127.0.0.1', ok); });
  base = `http://127.0.0.1:${serveur.address().port}`;
});

after(async () => {
  await new Promise((ok) => { serveur.close(ok); });
  await rm(dossier, { recursive: true, force: true });
});

const entete = (id) => ({ authorization: `Bearer ${signToken({ typ: 'session', sub: id, iat: Date.now(), exp: Date.now() + 60_000 }, secret)}` });
async function appel(qui, methode, chemin, corps) {
  const res = await fetch(`${base}${chemin}`, { method: methode, headers: { ...entete(qui), ...(corps ? { 'content-type': 'application/json' } : {}) }, body: corps ? JSON.stringify(corps) : undefined });
  const texte = await res.text();
  return { status: res.status, data: texte ? JSON.parse(texte) : null };
}
const envoyerImage = async (qui, chemin, image) => {
  const res = await fetch(`${base}${chemin}`, { method: 'POST', headers: entete(qui), body: image });
  return res.json();
};
const logement = (photos, titre = 'Studio lumineux') => ({
  categorie: 'Logement', titre, description: 'Très bien situé', photos, typeLocation: 'Studio', loyer: 400, surface: 30, chambres: 1, ville: 'Tunis', quartier: '', adresse: 'rue de Rome',
});
/** Publie comme le ferait le parcours normal : l'administrateur de test valide l'annonce. */
async function publier(qui, image, titre) {
  const { path: photo } = await envoyerImage(qui, '/photos', image);
  const creee = await appel(qui, 'POST', '/annonces', logement([photo], titre));
  if (creee.data.statut !== 'enAttente') return creee;
  return appel('admin', 'POST', `/annonces/${creee.data.id}/statut`, { statut: 'publiee' });
}

test('une photo déjà publiée est refusée, l’originale reste en ligne', async () => {
  const originale = await scene(1_000_003);
  const source = await publier('sami', originale, 'Originale de Sami');
  assert.equal(source.data.statut, 'publiee');

  const copie = await sharp(originale).resize(800).jpeg({ quality: 60 }).toBuffer();
  const verification = await envoyerImage('voleur', '/photos/verifier', copie);
  assert.equal(verification.correspondance.niveau, 'certaine');
  assert.equal(verification.correspondance.annonceCibleTitre, 'Originale de Sami');

  const refus = await publier('voleur', copie, 'Copie');
  assert.equal(refus.status, 409);
  assert.equal(refus.data.error, 'photo_deja_publiee');
  assert.match(refus.data.message, /changez-la/);

  const vues = (await appel('voleur', 'GET', '/annonces')).data.items;
  assert.ok(!vues.some((a) => a.titre === 'Copie'), 'aucune annonce créée');
  assert.ok(vues.some((a) => a.id === source.data.id));
});

test('après le refus, publier avec une autre photo fonctionne', async () => {
  const originale = await scene(1_100_009);
  await publier('sami', originale, 'Originale');
  assert.equal((await publier('autre', originale, 'Refusée')).status, 409);
  assert.equal((await publier('autre', await scene(1_200_007), 'Sa propre photo')).data.statut, 'publiee');
});

test('la modification d’une annonce ne peut pas ajouter une photo déjà publiée', async () => {
  const originale = await scene(1_300_021);
  await publier('sami', originale, 'Originale');
  const mienne = await publier('autre', await scene(1_400_017), 'Mon annonce');
  const { path: copie } = await envoyerImage('autre', '/photos', originale);
  const refus = await appel('autre', 'PUT', `/annonces/${mienne.data.id}`, logement([copie], 'Mon annonce'));
  assert.equal(refus.status, 409);
  const apres = (await appel('autre', 'GET', '/annonces')).data.items.find((a) => a.id === mienne.data.id);
  assert.equal(apres.photos.length, 1);
  assert.notEqual(apres.photos[0], copie);
});

test('réutiliser ses propres photos ne déclenche rien', async () => {
  const image = await scene(2_000_003);
  await publier('sami', image, 'Première');
  assert.equal((await envoyerImage('sami', '/photos/verifier', image)).correspondance, null);
  assert.equal((await publier('sami', image, 'Seconde')).data.statut, 'publiee');
});

test('il n’y a plus de statut bloqué ni de décision d’administrateur', async () => {
  assert.equal((await appel('admin', 'GET', '/admin/blocages')).status, 404);
  assert.equal((await appel('admin', 'POST', '/admin/annonces/x/decision', {})).status, 404);
  assert.equal((await appel('sami', 'POST', '/annonces/x/contester', {})).status, 404);
});

test('zone douteuse : l’IA décide, et sans IA rien n’est refusé', async () => {
  const image = await scene(5_000_011);
  await publier('sami', image, 'Douteuse');
  const reference = await analyserImage(image);
  const douteuses = [];
  for (const dx of [40, 48, 60, 72, 84]) {
    const recadree = await sharp(image).extract({ left: dx, top: 36, width: 1104 - dx, height: 828 }).jpeg().toBuffer();
    const d = ecart(await analyserImage(recadree), reference);
    if (d > SEUIL_CERTAIN && d <= SEUIL_DOUTE) douteuses.push(recadree);
  }
  assert.ok(douteuses.length >= 1, 'au moins un recadrage dans la zone douteuse');
  const doute = douteuses[0];

  verdictIa = { meme_image: false, meme_lieu: false, confiance: 0.9, raison: 'Pièces différentes' };
  assert.equal((await envoyerImage('autre', '/photos/verifier', doute)).correspondance, null);
  assert.ok(appelsIa >= 1);

  verdictIa = { meme_image: true, meme_lieu: true, confiance: 0.95, raison: 'Même prise de vue' };
  const confirmee = await envoyerImage('autre', '/photos/verifier', await sharp(doute).jpeg({ quality: 88 }).toBuffer());
  assert.equal(confirmee.correspondance?.niveau, 'confirmee_ia');

  verdictIa = 'panne';
  assert.equal((await envoyerImage('autre', '/photos/verifier', await sharp(doute).jpeg({ quality: 83 }).toBuffer())).correspondance, null);
});

test('une photo de messagerie n’est jamais comparée', async () => {
  const image = await scene(6_000_011);
  await envoyerImage('sami', '/photos', image);
  assert.equal((await envoyerImage('autre', '/photos/verifier', image)).correspondance, null);
});

test('le détail d’une annonce non publique n’est pas révélé', async () => {
  const image = await scene(7_000_003);
  const source = await publier('sami', image, 'Titre privé');
  await appel('sami', 'POST', `/annonces/${source.data.id}/statut`, { statut: 'archivee' });
  const { correspondance } = await envoyerImage('autre', '/photos/verifier', image);
  assert.equal(correspondance.niveau, 'certaine');
  assert.equal(correspondance.annonceCibleTitre, null);
  assert.equal(correspondance.photoCible, null);
});

test('une image non reconnue est refusée', async () => {
  const res = await fetch(`${base}/photos/verifier`, { method: 'POST', headers: entete('sami'), body: Buffer.from('pas une image') });
  assert.equal(res.status, 415);
});
