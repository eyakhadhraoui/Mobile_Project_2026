// Entraîne le modèle d'estimation de prix et écrit assets/modele_prix.json.
// Usage : node tool/entrainement_prix/entrainer.mjs ["Property Prices in Tunisia.csv"]
//
// Modèle : régression ridge sur le logarithme du prix. Elle reste assez petite
// pour être embarquée dans l'application et calculée sans connexion.
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const AUTRES = 'autres villes';

export function lireCsv(texte) {
  const lignes = []; let ligne = []; let champ = ''; let guillemets = false;
  for (let i = 0; i < texte.length; i++) {
    const c = texte[i];
    if (guillemets) {
      if (c === '"' && texte[i + 1] === '"') { champ += '"'; i++; } else if (c === '"') guillemets = false; else champ += c;
    } else if (c === '"') guillemets = true;
    else if (c === ',') { ligne.push(champ); champ = ''; } else if (c === '\n') { ligne.push(champ.replace(/\r$/, '')); lignes.push(ligne); ligne = []; champ = ''; } else champ += c;
  }
  if (champ || ligne.length) { ligne.push(champ); lignes.push(ligne); }
  const [tete, ...corps] = lignes;
  return corps.filter((l) => l.length === tete.length).map((l) => Object.fromEntries(tete.map((h, i) => [h, l[i]])));
}

const CATEGORIES = { Appartements: 'appartement', 'Maisons et Villas': 'maison', Colocations: 'colocation' };
const BORNES = {
  louer: { prix: [80, 15000], m2: [1.5, 60] },
  vendre: { prix: [15000, 5000000], m2: [150, 12000] },
};

/** Garde les logements exploitables : surface connue, prix et prix au m² plausibles. */
export function nettoyer(lignes) {
  const vus = new Set();
  const resultat = [];
  for (const l of lignes) {
    const categorie = CATEGORIES[l.category];
    const type = l.type === 'À Louer' ? 'louer' : l.type === 'À Vendre' ? 'vendre' : null;
    const surface = Number(l.size); const prix = Number(l.price);
    if (!categorie || !type || !(surface >= 10 && surface <= 1500)) continue;
    const b = BORNES[type];
    if (prix < b.prix[0] || prix > b.prix[1] || prix / surface < b.m2[0] || prix / surface > b.m2[1]) continue;
    const cle = [l.category, l.type, l.city, l.region, l.size, l.price, l.room_count, l.bathroom_count].join('|');
    if (vus.has(cle)) continue;
    vus.add(cle);
    resultat.push({
      type, categorie, surface, prix, ville: l.city.trim(), quartier: l.region.trim(),
      chambres: Number(l.room_count) >= 0 ? Number(l.room_count) : null,
      sdb: Number(l.bathroom_count) >= 0 ? Number(l.bathroom_count) : null,
    });
  }
  return resultat;
}

const cleQuartier = (r) => `${r.ville}|${r.quartier}`;
const quartierUtile = (r) => r.quartier.toLowerCase() !== AUTRES;

/** Colonnes fixes, puis une colonne par ville et par quartier assez représenté. */
function colonnes(donnees) {
  const parQuartier = new Map();
  for (const r of donnees) if (quartierUtile(r)) parQuartier.set(cleQuartier(r), (parQuartier.get(cleQuartier(r)) || 0) + 1);
  return {
    villes: [...new Set(donnees.map((r) => r.ville))].sort(),
    quartiers: [...parQuartier].filter(([, n]) => n >= 3).map(([k]) => k).sort(),
  };
}

const NB_FIXES = 8;
function vecteur(r, index) {
  const x = new Map([
    [0, 1], [1, Math.log(r.surface)], [2, Math.log(r.surface) ** 2],
    [3, r.chambres === null ? 0 : Math.min(r.chambres, 8)], [4, r.chambres === null ? 1 : 0],
    [5, r.sdb === null ? 0 : Math.min(r.sdb, 5)],
    [6, r.categorie === 'maison' ? 1 : 0], [7, r.categorie === 'colocation' ? 1 : 0],
  ]);
  const v = index.villes.get(r.ville);
  if (v !== undefined) x.set(v, 1);
  const q = index.quartiers.get(cleQuartier(r));
  if (q !== undefined) x.set(q, 1);
  return x;
}

function resoudre(A, b) {
  const n = b.length; const M = A.map((l, i) => [...l, b[i]]);
  for (let c = 0; c < n; c++) {
    let p = c; for (let i = c + 1; i < n; i++) if (Math.abs(M[i][c]) > Math.abs(M[p][c])) p = i;
    [M[c], M[p]] = [M[p], M[c]];
    for (let i = c + 1; i < n; i++) { const f = M[i][c] / M[c][c]; if (f) for (let j = c; j <= n; j++) M[i][j] -= f * M[c][j]; }
  }
  const x = new Array(n).fill(0);
  for (let i = n - 1; i >= 0; i--) { let s = M[i][n]; for (let j = i + 1; j < n; j++) s -= M[i][j] * x[j]; x[i] = s / M[i][i]; }
  return x;
}

export function ajuster(donnees, lambdaVille = 2, lambdaQuartier = 4) {
  const { villes, quartiers } = colonnes(donnees);
  const index = { villes: new Map(villes.map((v, i) => [v, NB_FIXES + i])), quartiers: new Map(quartiers.map((q, i) => [q, NB_FIXES + villes.length + i])) };
  const n = NB_FIXES + villes.length + quartiers.length;
  const A = Array.from({ length: n }, () => new Array(n).fill(0)); const b = new Array(n).fill(0);
  for (const r of donnees) {
    const x = [...vecteur(r, index)]; const y = Math.log(r.prix);
    for (const [i, vi] of x) { b[i] += vi * y; for (const [j, vj] of x) A[i][j] += vi * vj; }
  }
  for (let i = 0; i < n; i++) A[i][i] += i === 0 ? 1e-6 : i < NB_FIXES ? 0.01 : i < NB_FIXES + villes.length ? lambdaVille : lambdaQuartier;
  return { index, coef: resoudre(A, b), villes, quartiers };
}

export const predire = (m, r) => { let s = 0; for (const [i, v] of vecteur(r, m.index)) s += m.coef[i] * v; return s; };

const quantile = (v, q) => { const s = [...v].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(q * s.length))]; };

function melanger(t) { let g = 42; const a = [...t]; for (let i = a.length - 1; i > 0; i--) { g = (g * 1103515245 + 12345) % 2147483648; const j = g % (i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; }

/** Validation croisée : chaque annonce est prédite par un modèle qui ne l'a jamais vue. */
export function validation(donnees, plis = 5, opts = []) {
  const d = melanger(donnees); const res = [];
  for (let k = 0; k < plis; k++) {
    const train = d.filter((_, i) => i % plis !== k); const test = d.filter((_, i) => i % plis === k);
    const m = ajuster(train, ...opts);
    for (const r of test) res.push({ r, residu: Math.log(r.prix) - predire(m, r) });
  }
  return res;
}

function bilan(res) {
  const ape = res.map(({ r, residu }) => Math.abs(r.prix - r.prix / Math.exp(residu)) / r.prix);
  const y = res.map(({ r }) => Math.log(r.prix)); const moy = y.reduce((a, b) => a + b, 0) / y.length;
  const r2 = 1 - res.reduce((a, { residu }) => a + residu * residu, 0) / y.reduce((a, v) => a + (v - moy) ** 2, 0);
  return { n: res.length, erreurMediane: quantile(ape, 0.5), r2 };
}

function entrainer(fichier) {
  const toutes = nettoyer(lireCsv(readFileSync(fichier, 'utf8').replace(/^﻿/, '')));
  const modeles = {};
  for (const type of ['louer', 'vendre']) {
    const donnees = toutes.filter((r) => r.type === type);
    const res = validation(donnees);
    const residus = res.map((x) => x.residu);
    const m = ajuster(donnees);
    const nbQuartier = {}; const nbVille = {};
    for (const r of donnees) { nbVille[r.ville] = (nbVille[r.ville] || 0) + 1; if (quartierUtile(r)) nbQuartier[cleQuartier(r)] = (nbQuartier[cleQuartier(r)] || 0) + 1; }
    const b = bilan(res);
    const dansIntervalle = residus.filter((e) => e >= quantile(residus, 0.1) && e <= quantile(residus, 0.9)).length / residus.length;
    console.log(type, JSON.stringify({ ...b, dansIntervalle, largeur: [quantile(residus, 0.1), quantile(residus, 0.9)] }));
    // Exemples relus par les tests Dart : les deux calculs doivent donner le même prix.
    const controle = donnees.filter((_, i) => i % 400 === 0).slice(0, 6).map((r) => ({ ...r, attendu: predire(m, r) }));
    modeles[type] = {
      controle,
      fixes: m.coef.slice(0, NB_FIXES).map((c) => Number(c.toFixed(5))),
      villes: Object.fromEntries(m.villes.map((v) => [v, Number(m.coef[m.index.villes.get(v)].toFixed(4))])),
      quartiers: Object.fromEntries(m.quartiers.map((q) => [q, Number(m.coef[m.index.quartiers.get(q)].toFixed(4))])),
      nbVille, nbQuartier,
      residus: { bas: Number(quantile(residus, 0.1).toFixed(4)), haut: Number(quantile(residus, 0.9).toFixed(4)) },
      evaluation: { annonces: b.n, erreurMediane: Number(b.erreurMediane.toFixed(4)), r2: Number(b.r2.toFixed(4)) },
    };
  }
  return { source: path.basename(fichier), ...modeles };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const fichier = path.resolve(racine, process.argv[2] ?? 'Property Prices in Tunisia.csv');
  const sortie = path.join(racine, 'assets', 'modele_prix.json');
  writeFileSync(sortie, JSON.stringify(entrainer(fichier)));
  console.log('écrit', sortie);
}
