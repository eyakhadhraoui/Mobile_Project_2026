import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studenthub/widgets/compte_a_rebours.dart';

void main() {
  test('formatDuree omet les unités nulles de tête', () {
    expect(formatDuree(const Duration(seconds: 9)), '9 s');
    expect(formatDuree(const Duration(minutes: 2, seconds: 5)), '2 min 05 s');
    expect(
      formatDuree(const Duration(hours: 1, minutes: 1, seconds: 3)),
      '1 h 01 min 03 s',
    );
    expect(
      formatDuree(const Duration(days: 2, hours: 3, minutes: 4)),
      '2 j 03 h 04 min',
    );
  });

  testWidgets('décompte chaque seconde puis prévient une seule fois', (
    tester,
  ) async {
    var maintenant = DateTime.utc(2026, 11, 9, 12);
    var termine = 0;
    Future<void> avancer(int secondes) async {
      for (var i = 0; i < secondes; i++) {
        maintenant = maintenant.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CompteARebours(
          date: maintenant.add(const Duration(seconds: 3)),
          prefixe: 'Dans ',
          horloge: () => maintenant,
          onTermine: () => termine++,
        ),
      ),
    );
    expect(find.text('Dans 3 s'), findsOneWidget);

    await avancer(1);
    expect(find.text('Dans 2 s'), findsOneWidget);
    expect(termine, 0);

    await avancer(2);
    expect(find.text('Publication en cours…'), findsOneWidget);
    expect(termine, 0, reason: 'le serveur a une seconde de marge');

    await avancer(5);
    expect(termine, 1);
  });

  testWidgets('une nouvelle date relance le décompte', (tester) async {
    final maintenant = DateTime.utc(2026, 11, 9, 12);
    Widget ecran(int secondes) => MaterialApp(
      home: CompteARebours(
        date: maintenant.add(Duration(seconds: secondes)),
        horloge: () => maintenant,
      ),
    );

    await tester.pumpWidget(ecran(10));
    expect(find.text('10 s'), findsOneWidget);
    await tester.pumpWidget(ecran(70));
    expect(find.text('1 min 10 s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
