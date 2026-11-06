// Outils de texte partagés (détection de danger, géocodage, incidents).

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
};

/// Minuscules, sans accents, ponctuation remplacée par des espaces, espaces réduits.
/// « Résidence El-Manar, Bloc A » → « residence el manar bloc a ».
String normaliserTexte(String texte) {
  final buffer = StringBuffer();
  for (final caractere in texte.toLowerCase().split('')) {
    buffer.write(_accents[caractere] ?? caractere);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[’]'), "'")
      .replaceAll(RegExp(r'[^a-z0-9Ѐ-ӿ؀-ۿ]+'), ' ')
      .trim();
}

/// Remplace adresses e-mail et numéros de téléphone avant tout envoi à un
/// service externe : seule la description du problème est utile.
String masquerDonneesPersonnelles(String texte) => texte
    .replaceAll(RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+'), '[e-mail masqué]')
    .replaceAll(RegExp(r'(\+|00)?\d[\d\s.-]{6,}\d'), '[téléphone masqué]');
