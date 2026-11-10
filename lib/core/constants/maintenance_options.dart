class OptionItem {
  const OptionItem(this.value, this.label);

  final String value;
  final String label;
}

class MaintenanceOptions {
  const MaintenanceOptions._();

  static const categories = [
    OptionItem('electricite', 'Électricité'),
    OptionItem('plomberie', 'Plomberie'),
    OptionItem('chauffage', 'Chauffage'),
    OptionItem('serrurerie', 'Serrurerie'),
    OptionItem('humidite', 'Humidité'),
    OptionItem('autre', 'Autre'),
  ];

  static const rooms = [
    OptionItem('cuisine', 'Cuisine'),
    OptionItem('salle_de_bain', 'Salle de bain'),
    OptionItem('salon', 'Salon'),
    OptionItem('chambre', 'Chambre'),
    OptionItem('toilettes', 'Toilettes'),
    OptionItem('autre', 'Autre'),
  ];

  static const urgencies = [
    OptionItem('faible', 'Faible'),
    OptionItem('moyenne', 'Moyenne'),
    OptionItem('elevee', 'Élevée'),
    OptionItem('critique', 'Critique'),
  ];

  /// Libellé de [value], ou [value] lui-même si l'option est introuvable.
  static String labelOf(List<OptionItem> options, String value) {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return value;
  }
}
