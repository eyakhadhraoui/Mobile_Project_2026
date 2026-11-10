import assert from 'node:assert/strict';
import { test } from 'node:test';

import { ajuster, lireCsv, nettoyer, predire } from './entrainer.mjs';

const ligne = (surcharges) => ({
  category: 'Appartements', type: 'À Louer', size: '80', price: '700', city: 'Tunis', region: 'Lac',
  room_count: '2', bathroom_count: '1', ...surcharges,
});

test('le CSV gère les guillemets et les virgules', () => {
  assert.deepEqual(lireCsv('a,b\n"x,y",2\n'), [{ a: 'x,y', b: '2' }]);
});

test('un logement correct est conservé', () => {
  const [r] = nettoyer([ligne({})]);
  assert.deepEqual([r.type, r.categorie, r.surface, r.prix], ['louer', 'appartement', 80, 700]);
});

test('les annonces inexploitables sont écartées', () => {
  assert.equal(nettoyer([
    ligne({ size: '-1' }),
    ligne({ price: '99999999999' }),
    ligne({ price: '20' }),
    ligne({ size: '1400', price: '700' }), // prix au m² trop bas
    ligne({ category: 'Terrains et Fermes' }),
    ligne({ category: 'Locations de vacances' }), // prix à la nuit
  ]).length, 0);
});

test('les doublons ne comptent qu’une fois', () => {
  assert.equal(nettoyer([ligne({}), ligne({})]).length, 1);
});

test('une valeur inconnue (-1) reste possible pour les chambres', () => {
  assert.equal(nettoyer([ligne({ room_count: '-1' })])[0].chambres, null);
});

test('le modèle retrouve un loyer proportionnel à la surface et à la ville', () => {
  const donnees = [];
  for (let i = 0; i < 400; i++) {
    const surface = 40 + (i % 20) * 8;
    const chere = i % 2 === 0;
    donnees.push({ type: 'louer', categorie: 'appartement', surface, prix: surface * (chere ? 12 : 5), ville: chere ? 'A' : 'B', quartier: 'Autres villes', chambres: 2, sdb: 1 });
  }
  const m = ajuster(donnees);
  const base = { categorie: 'appartement', surface: 100, quartier: 'Autres villes', chambres: 2, sdb: 1 };
  const a = Math.exp(predire(m, { ...base, ville: 'A' }));
  const b = Math.exp(predire(m, { ...base, ville: 'B' }));
  assert.ok(Math.abs(a - 1200) / 1200 < 0.05, `A=${a}`);
  assert.ok(Math.abs(b - 500) / 500 < 0.05, `B=${b}`);
});
