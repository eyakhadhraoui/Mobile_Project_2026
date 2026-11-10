import { createHash } from 'node:crypto';

import sharp from 'sharp';

/**
 * Détecteur de photos déjà publiées, en deux temps :
 * 1. une empreinte exacte (SHA-256) et une empreinte perceptuelle (pHash), qui
 *    résiste au redimensionnement, à la recompression et aux retournements ;
 * 2. pour les ressemblances douteuses seulement, l'avis d'un modèle de vision.
 */

const TAILLE = 32;
const BASSES_FREQUENCES = 8;

/** Distances (sur 63 bits), mesurées par backend/detection_photos.test.mjs. */
export const SEUIL_CERTAIN = 6;
export const SEUIL_DOUTE = 14;

/** En dessous, l'image est presque unie (mur blanc…) : son pHash ne prouve rien. */
const ECART_TYPE_MIN = 10;

const COSINUS = Array.from({ length: BASSES_FREQUENCES }, (_, u) =>
  Array.from({ length: TAILLE }, (_, x) => Math.cos(((2 * x + 1) * u * Math.PI) / (2 * TAILLE))));

/** pHash : signe des basses fréquences (DCT) par rapport à leur médiane. */
function hachage(pixels) {
  const coefficients = [];
  for (let u = 0; u < BASSES_FREQUENCES; u++) {
    for (let v = 0; v < BASSES_FREQUENCES; v++) {
      if (u === 0 && v === 0) continue; // Luminosité moyenne de l'image.
      let somme = 0;
      for (let y = 0; y < TAILLE; y++) {
        for (let x = 0; x < TAILLE; x++) somme += pixels[y * TAILLE + x] * COSINUS[u][y] * COSINUS[v][x];
      }
      coefficients.push(somme);
    }
  }
  const tries = [...coefficients].sort((a, b) => a - b);
  const mediane = tries[Math.floor(tries.length / 2)];
  return coefficients.map((c) => (c > mediane ? '1' : '0')).join('');
}

const transposer = (p) => Array.from({ length: p.length }, (_, i) => p[(i % TAILLE) * TAILLE + Math.floor(i / TAILLE)]);
const retournerHorizontal = (p) => Array.from({ length: p.length }, (_, i) => p[Math.floor(i / TAILLE) * TAILLE + (TAILLE - 1 - (i % TAILLE))]);

/** Les 8 orientations possibles : 4 rotations, avec ou sans effet miroir. */
function orientations(pixels) {
  const resultat = [];
  let courant = pixels;
  for (let i = 0; i < 4; i++) {
    resultat.push(courant, retournerHorizontal(courant));
    courant = retournerHorizontal(transposer(courant));
  }
  return resultat;
}

export const sha256 = (buffer) => createHash('sha256').update(buffer).digest('hex');

/**
 * Analyse une image. `phash` vaut null si l'image est illisible ou presque unie :
 * seule la comparaison exacte s'applique alors.
 */
export async function analyserImage(buffer) {
  const sha = sha256(buffer);
  let pixels;
  try {
    const brut = await sharp(buffer, { failOn: 'none' }).rotate().greyscale().resize(TAILLE, TAILLE, { fit: 'fill' }).raw().toBuffer();
    pixels = Array.from(brut);
  } catch {
    return { sha256: sha, phash: null, variantes: [] };
  }
  const moyenne = pixels.reduce((a, b) => a + b, 0) / pixels.length;
  const ecart = Math.sqrt(pixels.reduce((a, b) => a + (b - moyenne) ** 2, 0) / pixels.length);
  if (ecart < ECART_TYPE_MIN) return { sha256: sha, phash: null, variantes: [] };
  const variantes = orientations(pixels).map(hachage);
  return { sha256: sha, phash: variantes[0], variantes };
}

export function distance(a, b) {
  let total = 0;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) total++;
  return total;
}

/**
 * Classe les photos existantes qui ressemblent à l'image analysée, de la plus
 * proche à la plus éloignée. [candidats] : [{ empreinte, ... }].
 */
export function chercherProches(analyse, candidats) {
  const proches = [];
  for (const candidat of candidats) {
    const { empreinte } = candidat;
    if (empreinte.sha256 === analyse.sha256) {
      proches.push({ ...candidat, distance: 0, exact: true });
    } else if (empreinte.phash && analyse.variantes.length) {
      const d = Math.min(...analyse.variantes.map((v) => distance(v, empreinte.phash)));
      if (d <= SEUIL_DOUTE) proches.push({ ...candidat, distance: d, exact: false });
    }
  }
  return proches.sort((a, b) => a.distance - b.distance);
}

/**
 * Appel du modèle de vision avec un quota horaire et une mémoire des paires
 * déjà jugées (la photo est vérifiée à l'ajout, puis à la publication).
 * Retourne null si l'avis n'a pas pu être obtenu.
 */
export function creerArbitre(comparer, { limiteHeure = 60 } = {}) {
  const verdicts = new Map();
  const appels = [];
  return async function arbitrer(a, b) {
    if (!comparer) return null;
    const cle = [sha256(a.buffer), sha256(b.buffer)].sort().join(':');
    if (verdicts.has(cle)) return verdicts.get(cle);
    const maintenant = Date.now();
    while (appels.length && appels[0] < maintenant - 3_600_000) appels.shift();
    if (appels.length >= limiteHeure) return null;
    appels.push(maintenant);
    try {
      const brut = await comparer(a, b);
      if (!brut || typeof brut !== 'object') return null;
      const verdict = {
        memeImage: brut.meme_image === true,
        memeLieu: brut.meme_lieu === true,
        confiance: typeof brut.confiance === 'number' ? Math.min(1, Math.max(0, brut.confiance)) : 0,
        raison: typeof brut.raison === 'string' ? brut.raison.slice(0, 300) : '',
      };
      if (verdicts.size >= 500) verdicts.delete(verdicts.keys().next().value);
      verdicts.set(cle, verdict);
      return verdict;
    } catch {
      return null; // Le détail de l'erreur peut citer la requête : rien n'est journalisé.
    }
  };
}

/** La ressemblance est confirmée : même image, ou même lieu avec une forte confiance. */
export const estConfirme = (verdict) => verdict.memeImage || (verdict.memeLieu && verdict.confiance >= 0.8);
