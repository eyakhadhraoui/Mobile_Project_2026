// Données de démonstration StudentHub : comptes, annonces, disponibilités,
// visites, demandes de location, avis, likes, commentaires et réclamations
// (avec historique et échanges propriétaire / étudiant).
//
// Usage (serveur ARRÊTÉ, depuis le dossier backend) :
//   npm run seed:demo            ajoute / remplace les données « demo_ »
//   npm run seed:demo -- --retirer   supprime uniquement les données « demo_ »
//
// Les données réelles ne sont jamais modifiées : seules les entrées dont
// l'identifiant commence par « demo_ » sont remplacées. Une sauvegarde des
// fichiers est faite dans data/sauvegardes/ avant toute écriture.
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import { hashPassword } from './auth.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const dataDir = process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR) : path.join(here, 'data');
const port = Number(process.env.PORT || 6500);
const retirer = process.argv.includes('--retirer');

export const MOT_DE_PASSE_DEMO = 'Demo2026!';
const DEMO = (id) => id.startsWith('demo_');
const DAY = 24 * 60 * 60 * 1000;
const pad = (n) => String(n).padStart(2, '0');

// ---------------------------------------------------------------------------
// Dates relatives à aujourd'hui (les créneaux restent dans le futur).
// ---------------------------------------------------------------------------
const today = new Date();
today.setHours(0, 0, 0, 0);
const jour = (offset) => {
  const d = new Date(today.getTime() + offset * DAY);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const estWeekEnd = (offset) => [0, 6].includes(new Date(today.getTime() + offset * DAY).getDay());
/** Prochain jour ouvré à partir de today + offset. */
const ouvre = (offset) => { let o = offset; while (estWeekEnd(o)) o++; return o; };
const iso = (offsetJours, heure = 10) => new Date(today.getTime() + offsetJours * DAY + heure * 3600 * 1000).toISOString();

// ---------------------------------------------------------------------------
// Comptes (mot de passe commun : Demo2026!)
// ---------------------------------------------------------------------------
const comptes = [
  { id: 'demo_admin', prenom: 'Admin', nom: 'StudentHub', email: 'admin@studenthub.test', role: 'locataire', telephone: '+216 70 000 001' },
  { id: 'demo_sami', prenom: 'Sami', nom: 'Ben Salah', email: 'sami.bensalah@studenthub.test', role: 'proprietaire', telephone: '+216 20 111 222' },
  { id: 'demo_leila', prenom: 'Leila', nom: 'Trabelsi', email: 'leila.trabelsi@studenthub.test', role: 'proprietaire', telephone: '+216 22 333 444' },
  { id: 'demo_karim', prenom: 'Karim', nom: 'Jaziri', email: 'karim.jaziri@studenthub.test', role: 'proprietaire', telephone: '+216 98 555 666' },
  { id: 'demo_yasmine', prenom: 'Yasmine', nom: 'Gharbi', email: 'yasmine.gharbi@studenthub.test', role: 'locataire', telephone: '+216 50 777 888' },
  { id: 'demo_omar', prenom: 'Omar', nom: 'Mansouri', email: 'omar.mansouri@studenthub.test', role: 'locataire', telephone: '+216 55 999 000' },
  { id: 'demo_anna', prenom: 'Anna', nom: 'Petrova', email: 'anna.petrova@studenthub.test', role: 'locataire', telephone: '+216 27 123 456' },
  { id: 'demo_mehdi', prenom: 'Mehdi', nom: 'Ayari', email: 'mehdi.ayari@studenthub.test', role: 'prestataire', telephone: '+216 29 654 321' },
];

// ---------------------------------------------------------------------------
// Annonces (adresses réelles de Tunis pour le géocodage et les temps de trajet)
// ---------------------------------------------------------------------------
const logement = (o) => ({ categorie: 'Logement', photos: [], autoriserCommentaires: true, motifModeration: '', datePublication: null, statut: 'publiee', ...o });
const autre = (o) => ({
  photos: [], autoriserCommentaires: true, motifModeration: '', datePublication: null, statut: 'publiee',
  typeLocation: '', loyer: 0, surface: 0, chambres: 0, etage: null, ville: '', quartier: '', adresse: '', ...o,
});

const annonces = [
  logement({
    id: 'demo_studio_manar', proprietaireId: 'demo_sami', createdAt: iso(-6),
    titre: 'Studio meublé à 10 min à pied de la FST',
    description: 'Studio lumineux entièrement meublé : lit double, bureau, kitchenette équipée, salle d’eau. Internet fibre inclus. Idéal pour un étudiant de la Faculté des Sciences ou de l’ENIT. Calme, au 2e étage avec ascenseur.',
    typeLocation: 'Studio', loyer: 450, surface: 25, chambres: 1, etage: 2, ville: 'Tunis', quartier: 'El Manar 2', adresse: 'Rue Abou Hamed El Ghazali',
  }),
  logement({
    id: 'demo_coloc_ariana', proprietaireId: 'demo_leila', createdAt: iso(-5),
    titre: 'Chambre en colocation entre étudiantes, Ariana',
    description: 'Chambre privée dans un S+3 partagé avec deux étudiantes. Salon, cuisine et machine à laver en commun. Charges (eau, électricité, internet) comprises. Proche des lignes de bus et du métro.',
    typeLocation: 'Colocation', loyer: 280, surface: 14, chambres: 1, etage: 1, ville: 'Ariana', quartier: 'Ariana Ville', adresse: 'Avenue Habib Bourguiba',
  }),
  logement({
    id: 'demo_s2_lafayette', proprietaireId: 'demo_karim', createdAt: iso(-4),
    titre: 'Appartement S+2 à Lafayette, idéal colocation',
    description: 'Appartement S+2 rénové, deux chambres, salon, cuisine indépendante et balcon. À deux pas du centre-ville et des transports. Possibilité de louer à deux étudiants.',
    typeLocation: 'Appartement', loyer: 900, surface: 75, chambres: 2, etage: 3, ville: 'Tunis', quartier: 'Lafayette', adresse: 'Avenue de la Liberté',
  }),
  logement({
    id: 'demo_studio_marsa', proprietaireId: 'demo_leila', createdAt: iso(-3),
    titre: 'Studio vue mer à La Marsa',
    description: 'Joli studio au calme avec vue sur la mer, terrasse partagée. Proche de la gare TGM pour rejoindre Tunis. Disponible dès le mois prochain.',
    typeLocation: 'Studio', loyer: 650, surface: 30, chambres: 1, etage: 4, ville: 'La Marsa', quartier: 'Marsa Plage', adresse: 'Rue du Maroc',
  }),
  logement({
    id: 'demo_chambre_bardo', proprietaireId: 'demo_sami', createdAt: iso(-2),
    titre: 'Chambre chez l’habitant au Bardo',
    description: 'Chambre meublée dans une maison familiale, entrée indépendante, salle de bain privée. Petit-déjeuner possible. Métro ligne 4 à proximité.',
    typeLocation: 'Chambre', loyer: 250, surface: 12, chambres: 1, etage: 0, ville: 'Tunis', quartier: 'Le Bardo', adresse: 'Rue de la République',
  }),
  logement({
    id: 'demo_s1_menzah', proprietaireId: 'demo_karim', createdAt: iso(-1),
    titre: 'Appartement S+1 à El Menzah 6 (en attente de validation)',
    description: 'S+1 meublé avec climatisation et chauffage, parking sécurisé. Annonce récente, en attente de validation par la modération.',
    typeLocation: 'Appartement', loyer: 700, surface: 55, chambres: 1, etage: 1, ville: 'Ariana', quartier: 'El Menzah 6', adresse: 'Rue Mustapha Abdessalem',
    statut: 'enAttente',
  }),
  logement({
    id: 'demo_coloc_ghazela', proprietaireId: 'demo_leila', createdAt: iso(0, 8),
    titre: 'Colocation 3 chambres près du Technopôle El Ghazala',
    description: 'Grande maison partagée, trois chambres disponibles à la rentrée de janvier. Proche de SUP’COM et ESPRIT. Publication programmée.',
    typeLocation: 'Colocation', loyer: 320, surface: 16, chambres: 1, etage: 0, ville: 'Ariana', quartier: 'Cité El Ghazala', adresse: 'Avenue de l’Environnement',
    statut: 'programmee', datePublication: iso(3, 9),
  }),
  logement({
    id: 'demo_studio_bab_saadoun', proprietaireId: 'demo_sami', createdAt: iso(-30),
    titre: 'Studio Bab Saadoun (loué)',
    description: 'Studio déjà loué pour l’année universitaire. Annonce archivée.',
    typeLocation: 'Studio', loyer: 380, surface: 20, chambres: 1, etage: 1, ville: 'Tunis', quartier: 'Bab Saadoun', adresse: 'Boulevard du 20 Mars',
    statut: 'archivee',
  }),
  autre({
    id: 'demo_residence_manar', categorie: 'Résidence', proprietaireId: 'demo_admin', createdAt: iso(-7),
    titre: 'Résidence universitaire El Manar : places disponibles',
    description: 'Il reste des places en chambre double pour le second semestre. Dossier à déposer au bureau de la résidence avant la fin du mois.',
  }),
  autre({
    id: 'demo_evenement_integration', categorie: 'Événement', proprietaireId: 'demo_yasmine', createdAt: iso(-2, 15),
    titre: 'Soirée d’intégration des nouveaux étudiants',
    description: 'Rendez-vous jeudi à 18 h au foyer de la résidence : jeux, musique et rencontre avec les associations étudiantes. Entrée libre.',
  }),
  autre({
    id: 'demo_avis_coupure', categorie: 'Avis', proprietaireId: 'demo_sami', createdAt: iso(-1, 9),
    titre: 'Coupure d’eau prévue mercredi à El Manar',
    description: 'La SONEDE annonce une coupure d’eau mercredi de 9 h à 14 h pour travaux. Pensez à faire des réserves.',
  }),
  autre({
    id: 'demo_vente_bureau', categorie: 'Autre', proprietaireId: 'demo_omar', createdAt: iso(-1, 18),
    titre: 'Vends bureau et chaise de bureau',
    description: 'Bureau en bois 120 × 60 cm et chaise réglable, très bon état. 120 DT les deux, à récupérer à Ariana.',
  }),
].map((a) => ({ ...a, updatedAt: a.createdAt }));

// ---------------------------------------------------------------------------
// Disponibilités de visite (jours ouvrés, 14 h - 18 h, créneaux de 30 min)
// ---------------------------------------------------------------------------
const plage = (id, ownerId) => {
  const exclus = [];
  for (let o = 1; o <= 14; o++) if (estWeekEnd(o)) exclus.push(jour(o));
  return {
    id, ownerId, startDate: jour(1), endDate: jour(14), startTime: '14:00', endTime: '18:00',
    durationMinutes: 30, breakMinutes: 0, excludedDates: exclus, active: true, createdAt: iso(-1),
  };
};
const disponibilites = [plage('demo_dispo_sami', 'demo_sami'), plage('demo_dispo_leila', 'demo_leila'), plage('demo_dispo_karim', 'demo_karim')];

// ---------------------------------------------------------------------------
// Visites (créneaux alignés sur les disponibilités)
// ---------------------------------------------------------------------------
const j1 = ouvre(1);
const j2 = ouvre(j1 + 1);
const visite = (id, dispo, ownerId, clientId, propertyId, offset, heure, status = 'confirmed', extra = {}) => {
  const [h, m] = heure.split(':').map(Number);
  const fin = h * 60 + m + 30;
  return {
    id, availabilityId: dispo, ownerId, clientId, propertyId,
    startAt: `${jour(offset)}T${heure}`, endAt: `${jour(offset)}T${pad(Math.floor(fin / 60))}:${pad(fin % 60)}`,
    status, createdAt: iso(-1, 11), updatedAt: iso(-1, 11), ...extra,
  };
};
const visites = [
  visite('demo_visite_yasmine_manar', 'demo_dispo_sami', 'demo_sami', 'demo_yasmine', 'demo_studio_manar', j1, '14:00'),
  visite('demo_visite_anna_marsa', 'demo_dispo_leila', 'demo_leila', 'demo_anna', 'demo_studio_marsa', j1, '15:30'),
  visite('demo_visite_omar_ariana', 'demo_dispo_leila', 'demo_leila', 'demo_omar', 'demo_coloc_ariana', j2, '16:00'),
  visite('demo_visite_mehdi_lafayette', 'demo_dispo_karim', 'demo_karim', 'demo_mehdi', 'demo_s2_lafayette', j2, '14:30', 'cancelled', { cancelledBy: 'demo_mehdi' }),
  visite('demo_visite_yasmine_bardo', 'demo_dispo_sami', 'demo_sami', 'demo_yasmine', 'demo_chambre_bardo', j2, '15:00'),
  visite('demo_visite_anna_ariana', 'demo_dispo_leila', 'demo_leila', 'demo_anna', 'demo_coloc_ariana', j1, '17:00'),
  visite('demo_visite_omar_lafayette', 'demo_dispo_karim', 'demo_karim', 'demo_omar', 'demo_s2_lafayette', j2, '16:30'),
  visite('demo_visite_mehdi_manar', 'demo_dispo_sami', 'demo_sami', 'demo_mehdi', 'demo_studio_manar', j2, '17:00'),
  // Visite passée (avant la demande de location d'Omar).
  { id: 'demo_visite_passee', availabilityId: 'demo_dispo_leila', ownerId: 'demo_leila', clientId: 'demo_omar', propertyId: 'demo_coloc_ariana',
    startAt: `${jour(-3)}T15:00`, endAt: `${jour(-3)}T15:30`, status: 'confirmed', createdAt: iso(-5), updatedAt: iso(-5) },
];

// ---------------------------------------------------------------------------
// Demandes de location
// ---------------------------------------------------------------------------
const demande = (id, ownerId, clientId, propertyId, annonce, status, extra) => ({
  id, ownerId, clientId, propertyId, visitId: null, monthlyRent: annonce.loyer, propertyType: annonce.typeLocation,
  startDate: jour(25), endDate: jour(25 + 300), duration: 10, paymentFrequency: 'MONTHLY', paymentMethod: 'BANK_TRANSFER',
  additionalMessage: '', status, createdAt: iso(-1, 12), updatedAt: iso(-1, 12), ...extra,
});
const parId = Object.fromEntries(annonces.map((a) => [a.id, a]));
const demandes = [
  demande('demo_demande_yasmine', 'demo_sami', 'demo_yasmine', 'demo_studio_manar', parId.demo_studio_manar, 'pending',
    { additionalMessage: 'Bonjour, je suis en 2e année à la FST. Le studio est-il disponible dès le mois prochain ?' }),
  demande('demo_demande_omar', 'demo_leila', 'demo_omar', 'demo_coloc_ariana', parId.demo_coloc_ariana, 'accepted',
    { visitId: 'demo_visite_passee', paymentMethod: 'CASH', additionalMessage: 'Merci pour la visite, la chambre me convient.' }),
  demande('demo_demande_anna', 'demo_leila', 'demo_anna', 'demo_studio_marsa', parId.demo_studio_marsa, 'refused',
    { duration: 5, endDate: jour(25 + 150), additionalMessage: 'Hello, I am an exchange student for one semester.' }),
];

// ---------------------------------------------------------------------------
// Avis (notes), likes et commentaires
// ---------------------------------------------------------------------------
const nom = (id) => { const c = comptes.find((x) => x.id === id); return `${c.prenom} ${c.nom}`; };
const notes = {
  demo_studio_manar: { demo_yasmine: 5, demo_omar: 4 },
  demo_coloc_ariana: { demo_omar: 4, demo_anna: 3 },
  demo_s2_lafayette: { demo_mehdi: 4 },
  demo_chambre_bardo: { demo_yasmine: 3 },
};
const likes = {
  demo_studio_manar: ['demo_yasmine', 'demo_omar', 'demo_anna'],
  demo_coloc_ariana: ['demo_omar'],
  demo_studio_marsa: ['demo_anna', 'demo_yasmine'],
  demo_evenement_integration: ['demo_omar', 'demo_anna', 'demo_mehdi'],
};
const commentaires = {
  demo_studio_manar: [
    ['demo_yasmine', 'Le loyer comprend-il l’électricité ?'],
    ['demo_sami', 'Bonjour, l’eau et internet sont inclus, l’électricité est en plus (environ 25 DT par mois).'],
  ],
  demo_studio_marsa: [
    ['demo_anna', 'Is it possible to visit on Saturday?'],
    ['demo_leila', 'Hello Anna, visits are on weekdays from 2 pm to 6 pm. You can book a slot in the app.'],
  ],
  demo_coloc_ariana: [
    ['demo_omar', 'La chambre est-elle meublée ?'],
    ['demo_leila', 'Oui : lit, armoire, bureau et chaise. Les draps ne sont pas fournis.'],
    ['demo_mehdi', 'La colocation accepte-t-elle les garçons ?'],
    ['demo_leila', 'Non, cette colocation est réservée aux étudiantes, désolée.'],
  ],
  demo_s2_lafayette: [
    ['demo_mehdi', 'Le parking est-il inclus dans le loyer ?'],
    ['demo_karim', 'Une place en sous-sol est disponible en plus, 30 DT par mois.'],
    ['demo_omar', 'Peut-on payer le loyer par trimestre ?'],
    ['demo_karim', 'Oui, par virement bancaire.'],
  ],
  demo_chambre_bardo: [
    ['demo_yasmine', 'Le petit-déjeuner est en option à combien ?'],
    ['demo_sami', '20 DT par mois, servi de 7 h à 9 h.'],
  ],
  demo_evenement_integration: [
    ['demo_omar', 'Super idée, je viendrai avec des amis !'],
    ['demo_anna', 'Can international students join too?'],
    ['demo_yasmine', 'Bien sûr Anna, tout le monde est le bienvenu !'],
  ],
  demo_avis_coupure: [['demo_omar', 'Merci pour l’info, je remplis des bouteilles ce soir.']],
  demo_vente_bureau: [
    ['demo_anna', 'Toujours disponible ?'],
    ['demo_omar', 'Oui, jusqu’à samedi. Vous pouvez passer à Ariana en fin d’après-midi.'],
  ],
  demo_residence_manar: [
    ['demo_mehdi', 'Quels documents faut-il fournir ?'],
    ['demo_admin', 'Attestation d’inscription, copie de la CIN ou du passeport et deux photos d’identité.'],
  ],
};

// ---------------------------------------------------------------------------
// Réclamations (historique + échanges). Les adresses reprennent celles des
// logements : carte des réclamations et incidents collectifs testables.
// ---------------------------------------------------------------------------
const heure = (offsetJours, h, m = 0) => new Date(today.getTime() + offsetJours * DAY + (h * 60 + m) * 60 * 1000).toISOString();
const message = (id, authorId, authorRole, text, langue, createdAt) => ({ id, authorId, authorRole, text, langue, createdAt, updatedAt: null, deleted: false });
const reclamation = (o) => ({ priority: 'moyenne', deleted: false, responses: [], ...o, history: o.history.map(([status, date]) => ({ status, date })) });

const reclamations = [
  reclamation({
    id: 'demo_rec_fuite_manar', userId: 'demo_yasmine', locationId: 'Rue Abou Hamed El Ghazali, El Manar 2, Tunis',
    subject: 'Fuite d’eau sous l’évier de la cuisine', category: 'fuiteEau', status: 'enCours', createdAt: heure(-3, 8, 40),
    description: 'Depuis ce matin, de l’eau coule sous l’évier dès que j’ouvre le robinet. J’ai mis une bassine mais le meuble commence à gonfler.',
    history: [['ouverte', heure(-3, 8, 40)], ['enCours', heure(-3, 11, 15)]],
    responses: [
      message('demo_rep_fuite_1', 'demo_sami', 'proprietaire', 'Bonjour Yasmine, merci pour le signalement. Le plombier passera demain entre 9 h et 11 h. Pouvez-vous laisser l’accès à la cuisine ?', 'fr', heure(-3, 11, 15)),
      message('demo_rep_fuite_2', 'demo_yasmine', 'etudiant', 'D’accord, je serai là toute la matinée. Merci !', 'fr', heure(-3, 12, 2)),
      message('demo_rep_fuite_3', 'demo_sami', 'proprietaire', 'Le joint du siphon a été changé. Dites-moi si la fuite revient.', 'fr', heure(-2, 10, 30)),
    ],
  }),
  reclamation({
    id: 'demo_rec_bruit_manar', userId: 'demo_yasmine', locationId: 'Rue Abou Hamed El Ghazali, El Manar 2, Tunis',
    subject: 'Voisins bruyants après minuit', category: 'voisinage', priority: 'faible', status: 'ouverte', createdAt: heure(-1, 9, 5),
    description: 'Les voisins du 3e étage mettent de la musique forte presque tous les soirs jusqu’à 2 h du matin. J’ai des examens la semaine prochaine.',
    history: [['ouverte', heure(-1, 9, 5)]],
  }),
  reclamation({
    id: 'demo_rec_chauffe_eau_ariana', userId: 'demo_omar', locationId: 'Avenue Habib Bourguiba, Ariana Ville, Ariana',
    subject: 'Chauffe-eau en panne, plus d’eau chaude', category: 'chauffage', status: 'ouverte', createdAt: heure(-1, 7, 50),
    description: 'Le chauffe-eau électrique ne chauffe plus depuis hier soir. Le voyant reste éteint alors que le disjoncteur est enclenché.',
    history: [['ouverte', heure(-1, 7, 50)]],
    responses: [
      message('demo_rep_chauffe_1', 'demo_leila', 'proprietaire', 'Bonjour Omar, j’ai appelé le technicien, il viendra jeudi après-midi. En attendant, ne démontez rien.', 'fr', heure(-1, 13, 20)),
    ],
  }),
  // Incident collectif : même bâtiment (chambres différentes), même catégorie, quelques heures d'écart.
  reclamation({
    id: 'demo_rec_courant_bloc_a_1', userId: 'demo_mehdi', locationId: 'Résidence universitaire El Manar, Bloc A, chambre 12',
    subject: 'Plus d’électricité dans la chambre', category: 'electricite', status: 'ouverte', createdAt: heure(0, 7, 10),
    description: 'Plus de courant dans ma chambre depuis 6 h ce matin. Les lumières du couloir ne marchent pas non plus.',
    history: [['ouverte', heure(0, 7, 10)]],
  }),
  reclamation({
    id: 'demo_rec_courant_bloc_a_2', userId: 'demo_anna', locationId: 'Résidence universitaire El Manar, Bloc A, chambre 27',
    subject: 'Coupure de courant au bloc A', category: 'electricite', status: 'ouverte', createdAt: heure(0, 9, 45),
    description: 'Il n’y a pas d’électricité dans ma chambre ni dans la cuisine commune du bloc A.',
    history: [['ouverte', heure(0, 9, 45)]],
    responses: [
      // Messages d'Anna en russe : le propriétaire voit « Traduire en français ».
      message('demo_rep_courant_1', 'demo_anna', 'etudiant', 'Света до сих пор нет, а завтра у меня экзамен. Когда починят?', 'ru', heure(0, 10, 5)),
      message('demo_rep_courant_2', 'demo_admin', 'proprietaire', 'Bonjour Anna, l’électricien de la résidence est prévenu. La coupure touche tout le bloc A : le courant devrait revenir avant 16 h.', 'fr', heure(0, 10, 40)),
      message('demo_rep_courant_3', 'demo_anna', 'etudiant', 'Спасибо большое!', 'ru', heure(0, 10, 52)),
    ],
  }),
  // Danger (gaz) : urgente, résolue.
  reclamation({
    id: 'demo_rec_gaz_lafayette', userId: 'demo_mehdi', locationId: 'Avenue de la Liberté, Lafayette, Tunis',
    subject: 'Odeur de gaz dans la cuisine', category: 'chauffage', priority: 'urgente', status: 'cloturee', createdAt: heure(-6, 19, 30),
    description: 'Forte odeur de gaz près de la cuisinière. J’ai fermé le robinet de gaz, ouvert les fenêtres et je suis sorti de l’appartement.',
    history: [['ouverte', heure(-6, 19, 30)], ['enCours', heure(-6, 19, 45)], ['cloturee', heure(-5, 12, 0)]],
    responses: [
      message('demo_rep_gaz_1', 'demo_karim', 'proprietaire', 'Vous avez bien fait. Ne rentrez pas, j’arrive avec un technicien dans 30 minutes.', 'fr', heure(-6, 19, 45)),
      message('demo_rep_gaz_2', 'demo_karim', 'proprietaire', 'Le raccord du flexible était usé : il a été remplacé et l’installation contrôlée. Tout est sécurisé.', 'fr', heure(-5, 12, 0)),
      message('demo_rep_gaz_3', 'demo_mehdi', 'etudiant', 'Merci pour la rapidité de l’intervention.', 'fr', heure(-5, 12, 30)),
    ],
  }),
  reclamation({
    id: 'demo_rec_frigo_lafayette', userId: 'demo_omar', locationId: 'Avenue de la Liberté, Lafayette, Tunis',
    subject: 'Réfrigérateur qui ne refroidit plus', category: 'equipement', status: 'enCours', createdAt: heure(-2, 16, 10),
    description: 'Le réfrigérateur fourni avec l’appartement fait du bruit mais ne refroidit plus. La nourriture se gâte.',
    history: [['ouverte', heure(-2, 16, 10)], ['enCours', heure(-1, 9, 0)]],
    responses: [
      message('demo_rep_frigo_1', 'demo_karim', 'proprietaire', 'Un réparateur passe vendredi. S’il ne peut pas le réparer, je le remplace.', 'fr', heure(-1, 9, 0)),
    ],
  }),
  reclamation({
    id: 'demo_rec_avance_marsa', userId: 'demo_anna', locationId: 'Rue du Maroc, Marsa Plage, La Marsa',
    subject: 'Avance non rendue après refus de la demande', category: 'proprietaire', priority: 'faible', status: 'cloturee', createdAt: heure(-9, 11, 0),
    description: 'J’avais versé 100 DT d’avance pour réserver le studio. Ma demande a été refusée et l’avance ne m’a pas été rendue.',
    history: [['ouverte', heure(-9, 11, 0)], ['cloturee', heure(-8, 15, 0)]],
    responses: [
      message('demo_rep_avance_1', 'demo_leila', 'proprietaire', 'Toutes mes excuses Anna, le remboursement a été fait par virement ce matin.', 'fr', heure(-8, 15, 0)),
      message('demo_rep_avance_2', 'demo_anna', 'etudiant', 'Я получила перевод, спасибо.', 'ru', heure(-8, 18, 20)),
    ],
  }),
];

// ---------------------------------------------------------------------------
// Écriture
// ---------------------------------------------------------------------------
async function lire(nomFichier, defaut) {
  try { return JSON.parse(await readFile(path.join(dataDir, `${nomFichier}.json`), 'utf8')); } catch (error) {
    if (error.code === 'ENOENT') return defaut;
    throw error;
  }
}
const ecrire = (nomFichier, valeur) => writeFile(path.join(dataDir, `${nomFichier}.json`), JSON.stringify(valeur, null, 2), 'utf8');

async function serveurActif() {
  try { return (await fetch(`http://127.0.0.1:${port}/health`, { signal: AbortSignal.timeout(1500) })).ok; } catch { return false; }
}

async function main() {
  if (await serveurActif()) {
    console.error(`Le serveur StudentHub tourne sur le port ${port} : arrêtez-le d’abord (il réécrirait ses données en mémoire).`);
    process.exit(1);
  }
  await mkdir(dataDir, { recursive: true });
  const fichiers = ['users', 'annonces', 'availability', 'visits', 'rental_requests', 'ratings', 'announcement_interactions', 'complaints'];

  // Sauvegarde avant modification.
  const sauvegarde = path.join(dataDir, 'sauvegardes', new Date().toISOString().replace(/[:.]/g, '-'));
  await mkdir(sauvegarde, { recursive: true });
  for (const f of fichiers) {
    try { await copyFile(path.join(dataDir, `${f}.json`), path.join(sauvegarde, `${f}.json`)); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }

  const users = await lire('users', {});
  const listes = {
    annonces: (await lire('annonces', [])).filter((a) => !DEMO(a.id)),
    availability: (await lire('availability', [])).filter((a) => !DEMO(a.id)),
    visits: (await lire('visits', [])).filter((v) => !DEMO(v.id)),
    rental_requests: (await lire('rental_requests', [])).filter((r) => !DEMO(r.id)),
    complaints: (await lire('complaints', [])).filter((c) => !DEMO(c.id)),
  };
  const ratings = await lire('ratings', {});
  const interactions = await lire('announcement_interactions', {});
  for (const id of Object.keys(users)) if (DEMO(id)) delete users[id];
  for (const id of Object.keys(ratings)) if (DEMO(id)) delete ratings[id];
  for (const id of Object.keys(interactions)) if (DEMO(id)) delete interactions[id];

  if (!retirer) {
    const emailsReels = new Set(Object.values(users).map((u) => u.email));
    for (const compte of comptes) {
      if (emailsReels.has(compte.email)) { console.warn(`Ignoré : ${compte.email} existe déjà (compte réel).`); continue; }
      users[compte.id] = { ...compte, createdAt: iso(-10), passwordHash: await hashPassword(MOT_DE_PASSE_DEMO) };
    }
    listes.annonces.push(...annonces);
    listes.availability.push(...disponibilites);
    listes.visits.push(...visites);
    listes.rental_requests.push(...demandes);
    listes.complaints.push(...reclamations);
    for (const [annonceId, parUtilisateur] of Object.entries(notes)) {
      ratings[annonceId] = Object.fromEntries(Object.entries(parUtilisateur).map(([userId, note]) => [userId, { note, author: nom(userId), createdAt: iso(-1, 13) }]));
    }
    for (const annonceId of new Set([...Object.keys(likes), ...Object.keys(commentaires)])) {
      interactions[annonceId] = {
        likes: (likes[annonceId] || []).map((userId) => ({ userId, author: nom(userId), createdAt: iso(-1, 14) })),
        comments: (commentaires[annonceId] || []).map(([userId, text], i) => ({ userId, author: nom(userId), text, createdAt: iso(-1, 15 + i) })),
      };
    }
  }

  await ecrire('users', users);
  for (const [f, valeur] of Object.entries(listes)) await ecrire(f, valeur);
  await ecrire('ratings', ratings);
  await ecrire('announcement_interactions', interactions);

  console.log(`Sauvegarde : ${sauvegarde}`);
  if (retirer) { console.log('Données de démonstration retirées.'); return; }
  const nbCommentaires = Object.values(commentaires).reduce((n, liste) => n + liste.length, 0);
  const nbMessages = reclamations.reduce((n, r) => n + r.responses.length, 0);
  console.log(`\n${comptes.length} comptes · ${annonces.length} annonces · ${disponibilites.length} plages de visite · ${visites.length} visites · ${demandes.length} demandes de location`);
  console.log(`${nbCommentaires} commentaires · ${reclamations.length} réclamations · ${nbMessages} messages d’échange`);
  console.log(`Mot de passe de tous les comptes : ${MOT_DE_PASSE_DEMO}\n`);
  for (const c of comptes) console.log(`  ${c.role.padEnd(12)} ${c.email}`);
  console.log('\nPour activer le compte administrateur et la modération, ajoutez dans backend/.env :');
  console.log('  ADMIN_EMAILS=admin@studenthub.test');
}

await main();
