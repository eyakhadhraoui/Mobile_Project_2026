import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:studenthub/providers/auth_provider.dart';
import 'package:studenthub/screens/auth/register_screen.dart';

void main() {
  testWidgets('la photo est proposée et la fac seulement aux étudiants', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: RegisterScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Ajouter une photo (facultatif)'), findsOneWidget);
    expect(find.text('Ma fac (facultatif)'), findsOneWidget);
    expect(find.text('Choisir sur la carte'), findsOneWidget);

    await tester.tap(find.text('Propriétaire'));
    await tester.pump();
    expect(find.text('Ma fac (facultatif)'), findsNothing);
    expect(find.text('Ajouter une photo (facultatif)'), findsOneWidget);

    await tester.tap(find.text('Étudiant / locataire'));
    await tester.pump();
    expect(find.text('Ma fac (facultatif)'), findsOneWidget);
  });
}
