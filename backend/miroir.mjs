/**
 * Double stockage : chaque table locale listée ici existe aussi en JSON
 * (`data/<table>.json`), et les données du serveur sont recopiées dans SQLite.
 * Les mots de passe, jetons et réglages ne passent jamais par ce mécanisme :
 * seules les tables de TABLES sont acceptées.
 */

const MAX_CHANGEMENTS = 100;
const MAX_TAILLE_LIGNE = 20_000;

export async function createMiroirRoutes({ store, fail, lireServeur }) {
  const donnees = {};
  const trajets = () => Object.values(donnees.covoiturage_trajets);
  const reservations = () => Object.values(donnees.covoiturage_reservations);

  /** Conducteur du trajet, ou personne qui y a une réservation. */
  const lieAuTrajet = (trajetId, id) =>
    trajets().some((t) => t.ligne?.id === trajetId && t.ligne.auteurId === id)
    || reservations().some((r) => r.ligne?.trajetId === trajetId && r.ligne.participantId === id);
  const conducteur = (trajetId, id) => trajets().some((t) => t.ligne?.id === trajetId && t.ligne.auteurId === id);
  const demande = (id) => Object.values(donnees.demandes).find((d) => d.ligne?.id === id)?.ligne;
  const partieDemande = (d, id) => Boolean(d) && [d.userId, d.assigneeId, d.proprietaireId].includes(id);
  const proprietaireDeLaLigne = (colonne) => ({ voir: (l, id) => l[colonne] === id, ecrire: (l, id) => l[colonne] === id });

  // voir / ecrire : qui peut lire ou modifier une ligne. prive : la table n'a pas
  // de colonne propriétaire, chaque compte a donc ses propres lignes.
  const TABLES = {
    covoiturage_trajets: { cle: ['id'], voir: () => true, ecrire: (l, id) => l.auteurId === id || lieAuTrajet(l.id, id) },
    covoiturage_reservations: {
      cle: ['id'],
      voir: (l, id) => l.participantId === id || conducteur(l.trajetId, id),
      ecrire: (l, id) => l.participantId === id || conducteur(l.trajetId, id),
    },
    covoiturage_evaluations: { cle: ['id'], voir: () => true, ecrire: (l, id) => l.evaluateurId === id },
    covoiturage_notifications: {
      cle: ['id'],
      voir: (l, id) => l.userId === id,
      // Une notification peut être créée pour l'autre personne du trajet.
      ecrire: (l, id) => l.userId === id || (Boolean(l.trajetId) && lieAuTrajet(l.trajetId, id)),
    },
    covoiturage_zones: { cle: ['userId'], ...proprietaireDeLaLigne('userId') },
    alertes_trajet: { cle: ['id'], ...proprietaireDeLaLigne('userId') },
    demandes: { cle: ['id'], voir: (l, id) => partieDemande(l, id), ecrire: (l, id) => partieDemande(l, id) },
    demande_historique: {
      cle: ['demandeId', 'date', 'statut'],
      voir: (l, id) => partieDemande(demande(l.demandeId), id),
      ecrire: (l, id) => partieDemande(demande(l.demandeId), id),
    },
    logements_loues: { cle: ['userId', 'annonceId'], ...proprietaireDeLaLigne('userId') },
    traductions: { cle: ['reponse_id', 'langue'], prive: true },
    trajets: { cle: ['depart', 'arrivee', 'mode'], prive: true },
    geocodage: { cle: ['adresse'], prive: true },
  };

  let revision = 0;
  for (const table of Object.keys(TABLES)) {
    donnees[table] = await store.load(table, {});
    for (const enregistrement of Object.values(donnees[table])) revision = Math.max(revision, enregistrement.rev);
  }

  const scalaire = (v) => v === null || ['string', 'number'].includes(typeof v);
  const cleValide = (config, cle) => Array.isArray(cle) && cle.length === config.cle.length && cle.every((v) => ['string', 'number'].includes(typeof v));
  const ligneValide = (config, cle, ligne) =>
    ligne && typeof ligne === 'object' && !Array.isArray(ligne)
    && Object.values(ligne).every(scalaire)
    && config.cle.every((colonne, i) => ligne[colonne] === cle[i])
    && JSON.stringify(ligne).length <= MAX_TAILLE_LIGNE;

  /** Retourne true si le changement est accepté. */
  function appliquer({ table, cle, ligne }, me) {
    const config = Object.hasOwn(TABLES, table) ? TABLES[table] : null;
    if (!config || !cleValide(config, cle)) return false;
    if (ligne !== null && !ligneValide(config, cle, ligne)) return false;
    const identifiant = config.prive ? JSON.stringify([me.id, ...cle]) : JSON.stringify(cle);
    const existant = donnees[table][identifiant];
    const ancienne = existant?.ligne ?? null;
    let nouvelle = ligne;
    if (!config.prive) {
      if (ancienne && !config.ecrire(ancienne, me.id)) return false;
      if (nouvelle && !config.ecrire(nouvelle, me.id)) return false;
      if (!ancienne && !nouvelle) return true;
      if (table === 'covoiturage_trajets' && ancienne && ancienne.auteurId !== me.id) {
        // Un passager ne touche qu'aux places et au statut du trajet.
        if (!nouvelle) return false;
        nouvelle = { ...ancienne, places: nouvelle.places, statut: nouvelle.statut };
      }
    }
    donnees[table][identifiant] = { cle, ligne: nouvelle, rev: ++revision, ...(config.prive ? { proprietaire: me.id } : {}) };
    return true;
  }

  function changementsDepuis(depuis, me) {
    const lignes = [];
    for (const [table, config] of Object.entries(TABLES)) {
      for (const { cle, ligne, rev, proprietaire } of Object.values(donnees[table])) {
        if (rev <= depuis) continue;
        const visible = config.prive ? proprietaire === me.id : ligne === null || config.voir(ligne, me.id);
        if (visible) lignes.push({ table, cle, ligne, rev });
      }
    }
    return lignes.sort((a, b) => a.rev - b.rev);
  }

  return [
    ['POST', /^\/miroir\/synchroniser$/, true, async ({ me, body }) => {
      const changements = Array.isArray(body.changements) ? body.changements : [];
      if (changements.length > MAX_CHANGEMENTS) fail(400, 'invalid_field', `${MAX_CHANGEMENTS} changements maximum par envoi.`);
      const depuis = Number.isInteger(body.depuis) && body.depuis >= 0 ? body.depuis : 0;
      const refuses = [];
      const modifiees = new Set();
      // Les parents d'abord, pour que les droits d'une ligne enfant soient vérifiables.
      const ordre = Object.keys(TABLES);
      const tries = changements.map((c, i) => ({ c, i })).sort((a, b) => ordre.indexOf(a.c?.table) - ordre.indexOf(b.c?.table));
      for (const { c, i } of tries) {
        if (c && typeof c === 'object' && appliquer(c, me)) modifiees.add(c.table);
        else refuses.push(i);
      }
      await Promise.all([...modifiees].filter((t) => Object.hasOwn(TABLES, t)).map((t) => store.save(t)));
      return [200, { revision, refuses, lignes: changementsDepuis(depuis, me), serveur: lireServeur(me) }];
    }],
  ];
}
