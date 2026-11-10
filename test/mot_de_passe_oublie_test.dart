import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:studenthub/providers/auth_provider.dart';
import 'package:studenthub/screens/auth/mot_de_passe_oublie_screen.dart';
import 'package:studenthub/services/auth_service.dart';
import 'package:studenthub/services/welcome_email_service.dart';

class _Mail extends WelcomeEmailService {
  _Mail({this.verification = WelcomeEmailStatus.verified});
  final WelcomeEmailStatus verification;
  final envois = <String>[];
  var verifications = 0;

  @override
  Future<WelcomeEmailStatus> sendPasswordResetCode({required String email}) async {
    envois.add(email);
    return WelcomeEmailStatus.sent;
  }

  @override
  Future<({WelcomeEmailStatus status, String? token})> verifyCodeForToken({
    required String email,
    required String code,
  }) async {
    verifications++;
    return (
      status: verification,
      token: verification == WelcomeEmailStatus.verified ? 'jeton' : null,
    );
  }
}

class _Auth extends AuthService {
  final recus = <(String, String, String)>[];
  var echecs = 0;

  @override
  Future<String?> restoreSession() async => null;

  @override
  Future<void> reinitialiserMotDePasse({
    required String email,
    required String nouveau,
    required String verificationToken,
  }) async {
    if (echecs > 0) {
      echecs--;
      throw Exception('Serveur injoignable');
    }
    recus.add((email, nouveau, verificationToken));
  }
}

Future<void> _ouvrir(WidgetTester tester, _Mail mail, _Auth auth) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(service: auth),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MotDePasseOublieScreen(email: 'omar@test.local', mail: mail),
                ),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

Future<void> _saisir(WidgetTester tester, {String confirmation = 'NouveauMdp2!'}) async {
  await tester.tap(find.text('Recevoir un code'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Code à 6 chiffres'), '123456');
  await tester.enterText(find.widgetWithText(TextFormField, 'Nouveau mot de passe'), 'NouveauMdp2!');
  await tester.enterText(find.widgetWithText(TextFormField, 'Confirmer le mot de passe'), confirmation);
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _valider(WidgetTester tester) async {
  await tester.tap(find.text('Changer le mot de passe'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('code puis nouveau mot de passe', (tester) async {
    final mail = _Mail();
    final auth = _Auth();
    await _ouvrir(tester, mail, auth);
    expect(find.text('Code à 6 chiffres'), findsNothing);
    await _saisir(tester);
    expect(mail.envois, ['omar@test.local']);
    await _valider(tester);
    expect(auth.recus, [('omar@test.local', 'NouveauMdp2!', 'jeton')]);
    expect(find.text('ouvrir'), findsOneWidget);
    expect(find.text('Mot de passe modifié. Connectez-vous.'), findsOneWidget);
  });

  testWidgets('confirmation différente : rien n’est envoyé', (tester) async {
    final mail = _Mail();
    final auth = _Auth();
    await _ouvrir(tester, mail, auth);
    await _saisir(tester, confirmation: 'AutreMdp3!');
    await _valider(tester);
    expect(find.text('Les mots de passe ne correspondent pas.'), findsOneWidget);
    expect(mail.verifications, 0);
    expect(auth.recus, isEmpty);
  });

  testWidgets('code incorrect : le mot de passe ne change pas', (tester) async {
    final mail = _Mail(verification: WelcomeEmailStatus.invalidCode);
    final auth = _Auth();
    await _ouvrir(tester, mail, auth);
    await _saisir(tester);
    await _valider(tester);
    expect(find.text('Code incorrect ou expiré.'), findsOneWidget);
    expect(auth.recus, isEmpty);
  });

  testWidgets('après une panne, le code déjà validé n’est pas redemandé', (tester) async {
    final mail = _Mail();
    final auth = _Auth()..echecs = 1;
    await _ouvrir(tester, mail, auth);
    await _saisir(tester);
    await _valider(tester);
    expect(auth.recus, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await _valider(tester);
    expect(mail.verifications, 1);
    expect(auth.recus, hasLength(1));
  });
}
