import assert from 'node:assert/strict';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  chargerGuides, construirePrompt, detecterDanger, estArabe, extraireJson, lireGuides, masquer, nettoyerReponse,
  rechercher, retirerReferencesInventees,
} from './assistant_reclamations.mjs';

const dossier = path.join(path.dirname(fileURLToPath(import.meta.url)), 'knowledge');
const guides = await chargerGuides(dossier);
const categorieDe = (texte) => rechercher(guides, texte)[0].categorie;
const documents = [{ id: 'g1', titre: 'Guide fuite', texte: 'Prévenir par écrit.' }];

test('chaque catégorie demandée a son guide', () => {
  const presentes = new Set(guides.map((g) => g.categorie));
  for (const c of ['plomberie', 'electricite', 'chauffage_climatisation', 'retard_loyer', 'voisinage', 'degradations', 'contrat', 'retard_reparations', 'caution', 'entretien', 'general']) {
    assert.ok(presentes.has(c), c);
  }
});

test('la recherche trouve le bon guide en français', () => {
  assert.equal(categorieDe('Il y a une fuite d’eau dans ma cuisine depuis hier'), 'plomberie');
  assert.equal(categorieDe('Mon locataire n’a pas payé son loyer ce mois-ci'), 'retard_loyer');
  assert.equal(categorieDe('Le voisin fait du bruit toute la nuit'), 'voisinage');
  assert.equal(categorieDe('On ne me rend pas ma caution'), 'caution');
});

test('la recherche trouve le bon guide en arabe', () => {
  assert.equal(categorieDe('يوجد تسرب ماء في المطبخ'), 'plomberie');
  assert.equal(categorieDe('الجيران يصنعون ضجيج في الليل'), 'voisinage');
});

test('sans mot reconnu, les conseils généraux sont utilisés', () => {
  assert.equal(rechercher(guides, 'xyzzy qwerty')[0].categorie, 'general');
});

test('les commentaires des guides ne sont pas indexés', () => {
  assert.equal(lireGuides('<!-- # Caché\ntexte -->\n# Visible\ncategorie: autre\nContenu').map((g) => g.titre).join(), 'Visible');
});

test('danger détecté en français et en arabe, pas sur un message ordinaire', () => {
  assert.ok(detecterDanger('Ça sent le GAZ dans la cuisine'));
  assert.ok(detecterDanger('هناك رائحة غاز'));
  assert.ok(!detecterDanger('Mon robinet goutte un peu'));
});

test('e-mails et téléphones ne partent pas vers le modèle', () => {
  const sortie = masquer('Écrivez à sami@test.tn ou au +216 50 777 888');
  assert.ok(!sortie.includes('sami@test.tn') && !sortie.includes('777'));
  const { contenu } = construirePrompt({ role: 'locataire', documents, precedents: [{ auteur: 'utilisateur', texte: 'tel 50777888' }], message: 'mail a@b.co' });
  assert.ok(!contenu.includes('50777888') && !contenu.includes('a@b.co'));
});

test('le rôle est donné au modèle', () => {
  assert.match(construirePrompt({ role: 'proprietaire', documents, precedents: [], message: 'x' }).systeme, /PROPRIÉTAIRE/);
  assert.match(construirePrompt({ role: 'locataire', documents, precedents: [], message: 'x' }).systeme, /LOCATAIRE/);
});

test('une référence juridique absente des documents est retirée', () => {
  const r = retirerReferencesInventees('Prévenez-le. Selon l’article 12 du code, il doit payer. Gardez les preuves.', documents);
  assert.equal(r.texte, 'Prévenez-le. Gardez les preuves.');
  assert.ok(r.retire);
});

test('une référence présente dans les documents est conservée', () => {
  const docs = [{ id: 'l', titre: 'Loi', texte: 'Selon l’article 12 du contrat type.' }];
  assert.ok(!retirerReferencesInventees('Voir article 12.', docs).retire);
});

test('la référence arabe inventée est retirée', () => {
  const r = retirerReferencesInventees('احتفظ بالأدلة. حسب الفصل 25 يجب الدفع.', documents);
  assert.ok(r.retire && !r.texte.includes('25'));
});

test('les valeurs hors liste sont remplacées et les sources inventées écartées', () => {
  const n = nettoyerReponse({ reponse: 'Bonjour', categorie: 'x', urgence: 'max', personne_concernee: 'y', sources: ['g1', 'g1', 'faux'], informations: [{ champ: 'Lieu', valeur: 'Cuisine' }, 'bad'], questions: ['A', 2] }, { documents, message: 'robinet' });
  assert.equal(n.analyse.categorie, 'autre');
  assert.equal(n.analyse.urgence, 'moyen');
  assert.equal(n.analyse.personneConcernee, 'indetermine');
  assert.deepEqual(n.sources, [{ id: 'g1', titre: 'Guide fuite' }]);
  assert.deepEqual(n.analyse.informations, [{ champ: 'Lieu', valeur: 'Cuisine' }]);
  assert.deepEqual(n.analyse.questions, ['A']);
});

test('un danger impose l’urgence élevée et les consignes, quoi que dise le modèle', () => {
  const n = nettoyerReponse({ reponse: 'Ok', urgence: 'faible' }, { documents, message: 'odeur de gaz' });
  assert.equal(n.analyse.urgence, 'eleve');
  assert.match(n.texte, /198/);
  const ar = nettoyerReponse({ reponse: 'حسنا' }, { documents, message: 'رائحة غاز في البيت' });
  assert.match(ar.texte, /السلامة/);
});

test('une référence retirée demande l’avis d’un professionnel', () => {
  const n = nettoyerReponse({ reponse: 'Conseil. Article 9 impose un délai.' }, { documents, message: 'x' });
  assert.ok(n.analyse.avisProfessionnel);
});

test('une réponse vide est refusée', () => {
  assert.throws(() => nettoyerReponse({ reponse: '  ' }, { documents, message: 'x' }));
});

test('le JSON est lu même entouré de texte', () => {
  assert.deepEqual(extraireJson('```json\n{"a":1}\n```'), { a: 1 });
  assert.throws(() => extraireJson('pas de json'));
});

test('détection de la langue arabe', () => {
  assert.ok(estArabe('يوجد تسرب ماء'));
  assert.ok(!estArabe('Il y a une fuite'));
});
