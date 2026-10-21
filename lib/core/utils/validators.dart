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
}
