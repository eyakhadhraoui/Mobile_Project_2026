import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:studenthub/providers/auth_provider.dart';
import 'package:studenthub/screens/auth/login_screen.dart';
import 'package:studenthub/services/auth_service.dart';

class _FakeAuthService extends AuthService {
  @override
  Stream<String?> get authStateChanges => const Stream<String?>.empty();

  @override
  Future<String?> getCurrentUserId() async => null;
}

void main() {
  testWidgets('shows the StudentHub sign-in screen', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(service: _FakeAuthService()),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bon retour !'), findsOneWidget);
    expect(find.text('Adresse e-mail ou téléphone'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
