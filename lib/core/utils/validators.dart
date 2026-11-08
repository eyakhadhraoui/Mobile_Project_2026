/// Niveau de robustesse d'un mot de passe, calculé localement.
enum ForceMotDePasse { faible, moyen, fort }

extension ForceMotDePasseLibelle on ForceMotDePasse {
  String get libelle => switch (this) {
    ForceMotDePasse.faible => 'Faible',
    ForceMotDePasse.moyen => 'Moyen',
    ForceMotDePasse.fort => 'Fort',
  };
}

/// Longueur minimale d'un nouveau mot de passe (règle de l'inscription).
const longueurMinimaleMotDePasse = 8;

/// Force d'un mot de passe selon sa longueur et la variété des caractères
/// (majuscules, minuscules, chiffres, symboles). Calcul 100 % local.
/// - faible : moins de 8 caractères, ou une seule famille de caractères ;
/// - fort : 12 caractères et au moins 3 familles, ou 10 caractères et les 4 ;
/// - moyen : les autres cas.
ForceMotDePasse forceMotDePasse(String motDePasse) {
  final longueur = motDePasse.runes.length;
  final familles = [
    RegExp(r'[A-Z]'),
    RegExp(r'[a-z]'),
    RegExp(r'[0-9]'),
    RegExp(r'[^A-Za-z0-9]'),
  ].where((famille) => famille.hasMatch(motDePasse)).length;
  if (longueur < longueurMinimaleMotDePasse || familles <= 1) return ForceMotDePasse.faible;
  if ((longueur >= 12 && familles >= 3) || (longueur >= 10 && familles == 4)) return ForceMotDePasse.fort;
  return ForceMotDePasse.moyen;
}

class Validators {
  const Validators._();

  static String? required(String? value, {String label = 'Ce champ'}) {
    if (value == null || value.trim().isEmpty) {
      return '$label est obligatoire.';
    }
    return null;
  }

  static String? email(String? value) {
    final requiredError = required(value, label: 'L\'email');
    if (requiredError != null) return requiredError;

    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(value!.trim())) {
      return 'Adresse email invalide.';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.length < 6) {
      return 'Le mot de passe doit contenir au moins 6 caractères.';
    }
    return null;
  }

  /// Nouveau mot de passe (inscription, changement) : 8 caractères minimum.
  static String? nouveauMotDePasse(String? value) {
    if (value == null || value.length < longueurMinimaleMotDePasse) {
      return 'Utilisez au moins $longueurMinimaleMotDePasse caractères.';
    }
    return null;
  }
}
