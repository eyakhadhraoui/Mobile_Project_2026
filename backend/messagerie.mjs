/**
 * Messagerie entre un locataire et le propriétaire d'une annonce.
 * Une conversation = une annonce + un locataire. Seuls ses deux participants
 * y ont accès : un tiers, même administrateur, reçoit une erreur 404.
 */

const ID_CLIENT = /^[A-Za-z0-9_-]{1,100}$/;
const LANGUE = /^[a-z]{2}$/;
const MAX_PHOTOS = 4;
const MAX_MESSAGES_RENVOYES = 200;

export async function createMessagerieRoutes({ store, users, annonces, visits, rentals, photos, photoPath, fail, text, newId, displayName, partage = {} }) {
  const conversations = await store.load('conversations', []);
  const messages = await store.load('messages', {});
  partage.messagerie = { conversations, messages };

  /** Le locataire a déjà une visite ou une demande de location sur cette annonce. */
  const aUnLien = (annonceId, locataireId) =>
    visits.some((v) => v.propertyId === annonceId && v.clientId === locataireId)
    || rentals.some((r) => r.propertyId === annonceId && r.clientId === locataireId);

  const participante = (id, me) => {
    const conversation = conversations.find((c) => c.id === id && (c.locataireId === me.id || c.proprietaireId === me.id));
    return conversation || fail(404, 'not_found', 'Conversation introuvable.');
  };

  function vue(conversation, me) {
    const fil = messages[conversation.id] || [];
    const dernier = fil.at(-1) ?? null;
    const lu = conversation.lu[me.id] ?? '';
    const estProprietaire = conversation.proprietaireId === me.id;
    const annonce = annonces.find((a) => a.id === conversation.annonceId);
    return {
      id: conversation.id,
      annonceId: conversation.annonceId,
      annonceTitre: annonce?.titre ?? conversation.annonceTitre,
      annoncePhoto: annonce?.photos?.[0] ?? null,
      interlocuteurNom: displayName(estProprietaire ? conversation.locataireId : conversation.proprietaireId),
      estProprietaire,
      dernierMessage: dernier && { texte: dernier.texte, nbPhotos: dernier.photos.length, auteurId: dernier.auteurId, createdAt: dernier.createdAt },
      nonLus: fil.filter((m) => m.auteurId !== me.id && m.createdAt > lu).length,
      updatedAt: conversation.updatedAt,
    };
  }

  function validerPhotos(valeur, me) {
    const liste = Array.isArray(valeur) ? valeur : [];
    if (liste.length > MAX_PHOTOS) fail(400, 'invalid_field', `${MAX_PHOTOS} photos maximum par message.`);
    for (const photo of liste) {
      const nom = typeof photo === 'string' ? photo.match(photoPath)?.[1] : null;
      if (!nom || photos[nom]?.ownerId !== me.id) fail(400, 'invalid_photo', 'Photo invalide : ajoutez-la de nouveau.');
    }
    return [...new Set(liste)];
  }

  return [
    ['GET', /^\/conversations$/, true, async ({ me }) => {
      // Une conversation ouverte sans message envoyé n'encombre pas la liste.
      const miennes = conversations.filter((c) => (c.locataireId === me.id || c.proprietaireId === me.id) && messages[c.id]?.length);
      return [200, miennes.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)).map((c) => vue(c, me))];
    }],

    // Le locataire écrit depuis une annonce publiée. Le propriétaire ne peut
    // écrire le premier qu'à quelqu'un qui a déjà demandé une visite ou une location.
    ['POST', /^\/conversations$/, true, async ({ me, body }) => {
      const annonce = annonces.find((a) => a.id === body.annonceId) || fail(404, 'not_found', 'Annonce introuvable.');
      const estProprietaire = annonce.proprietaireId === me.id;
      const locataireId = estProprietaire ? body.locataireId : me.id;
      if (estProprietaire) {
        if (typeof locataireId !== 'string' || !users[locataireId] || !aUnLien(annonce.id, locataireId)) {
          fail(403, 'forbidden', 'Vous pouvez écrire aux personnes qui ont demandé une visite ou une location.');
        }
      } else if ((annonce.categorie !== 'Logement' || annonce.statut !== 'publiee') && !aUnLien(annonce.id, me.id)) {
        fail(409, 'not_available', 'Ce logement n’est pas disponible.');
      }
      const existante = conversations.find((c) => c.annonceId === annonce.id && c.locataireId === locataireId);
      if (existante) return [200, vue(existante, me)];
      const maintenant = new Date().toISOString();
      const conversation = {
        id: newId(), annonceId: annonce.id, annonceTitre: annonce.titre, locataireId,
        proprietaireId: annonce.proprietaireId, lu: {}, createdAt: maintenant, updatedAt: maintenant,
      };
      conversations.push(conversation);
      await store.save('conversations');
      return [201, vue(conversation, me)];
    }],

    ['GET', /^\/conversations\/([A-Za-z0-9_-]{1,100})\/messages$/, true, async ({ me, req, params }) => {
      const conversation = participante(params[0], me);
      const fil = messages[conversation.id] || [];
      const etag = `"${fil.length}-${fil.at(-1)?.id ?? '0'}"`;
      if (req.headers['if-none-match'] === etag) return [304, undefined, { etag }];
      const dernierRecu = fil.filter((m) => m.auteurId !== me.id).at(-1);
      if (dernierRecu && (conversation.lu[me.id] ?? '') < dernierRecu.createdAt) {
        conversation.lu[me.id] = dernierRecu.createdAt;
        await store.save('conversations');
      }
      return [200, { conversation: vue(conversation, me), messages: fil.slice(-MAX_MESSAGES_RENVOYES) }, { etag }];
    }],

    ['POST', /^\/conversations\/([A-Za-z0-9_-]{1,100})\/messages$/, true, async ({ me, body, params }) => {
      const conversation = participante(params[0], me);
      const clientId = typeof body.clientId === 'string' && ID_CLIENT.test(body.clientId) ? body.clientId : null;
      const fil = messages[conversation.id] || [];
      // Envoi rejoué depuis la file hors ligne : le message n'apparaît qu'une fois.
      const deja = clientId && fil.find((m) => m.auteurId === me.id && m.clientId === clientId);
      if (deja) return [200, deja];
      const texte = text(body.texte ?? '', 0, 2000, 'Le message');
      const listePhotos = validerPhotos(body.photos, me);
      if (!texte && listePhotos.length === 0) fail(400, 'invalid_field', 'Écrivez un message ou ajoutez une photo.');
      const message = {
        id: newId(), auteurId: me.id, texte, photos: listePhotos,
        langue: typeof body.langue === 'string' && LANGUE.test(body.langue) ? body.langue : 'fr',
        clientId, createdAt: new Date().toISOString(),
      };
      fil.push(message);
      messages[conversation.id] = fil;
      conversation.updatedAt = message.createdAt;
      await Promise.all([store.save('messages'), store.save('conversations')]);
      return [201, message];
    }],
  ];
}
