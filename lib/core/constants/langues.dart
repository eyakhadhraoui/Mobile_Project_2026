/// Langues proposées pour la lecture des échanges (code ISO 639-1 → nom en français).
const languesDisponibles = <String, String>{
  'fr': 'français',
  'en': 'anglais',
  'ar': 'arabe',
  'ru': 'russe',
  'es': 'espagnol',
  'de': 'allemand',
  'tr': 'turc',
};

/// Langue par défaut d'un compte.
const langueParDefaut = 'fr';

/// Code accepté, sinon la langue par défaut.
String langueValide(Object? code) => languesDisponibles.containsKey(code) ? code! as String : langueParDefaut;

/// Nom affiché d'une langue (ex. « russe »).
String nomLangue(String code) => languesDisponibles[code] ?? code;
