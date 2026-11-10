import 'package:flutter_test/flutter_test.dart';
import 'package:studenthub/screens/chat/ai_chat_screen.dart';

void main() {
  test('retire le gras et transforme les listes', () {
    expect(
      texteAssistant('Voici :\n\n*   **Consulter les annonces** ?\n* Publier'),
      'Voici :\n\n• Consulter les annonces ?\n• Publier',
    );
  });

  test('laisse le texte normal intact', () {
    expect(texteAssistant('Prix : 2 * 100 DT'), 'Prix : 2 * 100 DT');
  });
}
