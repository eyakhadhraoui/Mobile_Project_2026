import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:studenthub/core/utils/validators.dart';
import 'package:studenthub/providers/mot_de_passe_provider.dart';
import 'package:studenthub/services/mot_de_passe_service.dart';
import 'package:studenthub/widgets/indicateur_mot_de_passe.dart';

// SHA-1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
const _hashComplet = '5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8';
const _suffixePassword = '1E4C9B93F3F0682250B6CF8331B7EE68FD8';

/// Réponse simulée de /range/5BAA6 (avec quelques lignes de remplissage à 0).
String _reponse({bool avecPassword = true, int nombre = 9659365}) => [
  '003D68EB55068C33ACE09247EE4C639306B:3',
  if (avecPassword) '$_suffixePassword:$nombre',
  '012C192B2F16F82EA0EB9EF18D9D539B0DD:0',
  'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:0',
].join('\r\n');

void main() {
  group('MotDePasseService', () {
    test('a) « password » : suffixe présent dans la réponse → résultat > 0', () async {
      final service = MotDePasseService(client: MockClient((_) async => http.Response(_reponse(), 200)));
      expect(await service.nombreDeFuites('password'), 9659365);
    });

    test('b) suffixe absent → 0', () async {
      final service = MotDePasseService(
        client: MockClient((_) async => http.Response(_reponse(avecPassword: false), 200)),
      );
      expect(await service.nombreDeFuites('password'), 0);
    });

    test('c) seuls les 5 premiers caractères du hash sont envoyés, avec Add-Padding', () async {
      late http.Request envoyee;
      final service = MotDePasseService(
        client: MockClient((request) async {
          envoyee = request;
          return http.Response(_reponse(), 200);
        }),
      );
      await service.nombreDeFuites('password');
      final url = envoyee.url.toString();
      expect(url, endsWith('/range/5BAA6'));
      expect(RegExp(r'/range/[0-9A-F]{5}$').hasMatch(url), isTrue);
      // Le domaine « pwnedpasswords » contient le mot « password » : on vérifie
      // donc le chemin et les paramètres, seule partie qui dépend du mot de passe.
      expect(envoyee.url.path, '/range/5BAA6');
      expect(envoyee.url.query, isEmpty);
      expect(envoyee.url.path, isNot(contains('password')));
      expect(url.toUpperCase(), isNot(contains(_hashComplet)));
      expect(url.toUpperCase(), isNot(contains(_suffixePassword)));
      expect(envoyee.method, 'GET');
      expect(envoyee.headers['Add-Padding'], 'true');
      expect(envoyee.body, isEmpty);
    });

    test('d) statut 500 → ServiceIndisponibleException', () async {
      final service = MotDePasseService(client: MockClient((_) async => http.Response('erreur', 500)));
      expect(service.nombreDeFuites('password'), throwsA(isA<ServiceIndisponibleException>()));
    });

    test('d) délai dépassé → ServiceIndisponibleException', () async {
      final service = MotDePasseService(
        delai: const Duration(milliseconds: 50),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return http.Response(_reponse(), 200);
        }),
      );
      expect(service.nombreDeFuites('password'), throwsA(isA<ServiceIndisponibleException>()));
    });

    test('d) hors ligne (SocketException) → ServiceIndisponibleException', () async {
      final service = MotDePasseService(client: MockClient((_) async => throw const SocketException('hors ligne')));
      final erreur = await service.nombreDeFuites('password').then<Object?>((_) => null, onError: (Object e) => e);
      expect(erreur, isA<ServiceIndisponibleException>());
      // Le message ne révèle ni le mot de passe ni son empreinte.
      expect(erreur.toString(), isNot(contains('password')));
      expect(erreur.toString().toUpperCase(), isNot(contains('5BAA6')));
    });

    test('e) ligne de padding (nombre 0) ignorée, même avec le bon suffixe', () {
      expect(MotDePasseService.compterSuffixe('$_suffixePassword:0\nABC:5', _suffixePassword), 0);
      expect(
        MotDePasseService.compterSuffixe('$_suffixePassword:0\n${_suffixePassword.toLowerCase()}:12', _suffixePassword),
        12,
      );
      expect(MotDePasseService.compterSuffixe('ligne illisible\n\n', _suffixePassword), 0);
    });
  });

  group('f) forceMotDePasse', () {
    test('faible', () {
      expect(forceMotDePasse('Ab1!'), ForceMotDePasse.faible); // trop court
      expect(forceMotDePasse('abcdefghijkl'), ForceMotDePasse.faible); // une seule famille
      expect(forceMotDePasse('12345678'), ForceMotDePasse.faible);
    });
    test('moyen', () {
      expect(forceMotDePasse('Abcdefg1'), ForceMotDePasse.moyen);
      expect(forceMotDePasse('motdepasse12'), ForceMotDePasse.moyen);
    });
    test('fort', () {
      expect(forceMotDePasse('Abcdef1!xyz#'), ForceMotDePasse.fort);
      expect(forceMotDePasse('Logement2026'), ForceMotDePasse.fort); // 12 car., 3 familles
      expect(forceMotDePasse('Ab1!efghij'), ForceMotDePasse.fort); // 10 car., 4 familles
    });
    test('règle de longueur des formulaires : 8 caractères', () {
      expect(Validators.nouveauMotDePasse('Abc1234'), isNotNull);
      expect(Validators.nouveauMotDePasse('Abc12345'), isNull);
    });
  });

  group('MotDePasseProvider', () {
    test('anti-rebond : un seul appel pour une saisie rapide, rien sous 8 caractères', () async {
      var appels = 0;
      final provider = MotDePasseProvider(
        antiRebond: const Duration(milliseconds: 30),
        service: MotDePasseService(
          client: MockClient((_) async {
            appels++;
            return http.Response(_reponse(avecPassword: false), 200);
          }),
        ),
      );
      addTearDown(provider.dispose);
      provider.surSaisie('court');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(appels, 0);
      expect(provider.etat, EtatVerificationMotDePasse.idle);

      for (final saisie in ['Logement', 'Logement2', 'Logement20', 'Logement2026']) {
        provider.surSaisie(saisie);
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(appels, 1);
      expect(provider.etat, EtatVerificationMotDePasse.sur);

      // Validation du formulaire sans nouvelle frappe : pas de nouvel appel.
      expect(await provider.verifierMotDePasse('Logement2026'), EtatVerificationMotDePasse.sur);
      expect(appels, 1);
    });

    test('une réponse arrivée après une nouvelle frappe est ignorée', () async {
      final premiere = Completer<http.Response>();
      final provider = MotDePasseProvider(
        service: MotDePasseService(client: MockClient((_) => premiere.future)),
      );
      addTearDown(provider.dispose);
      final verification = provider.verifierMotDePasse('password');
      expect(provider.etat, EtatVerificationMotDePasse.loading);
      provider.surSaisie('Autre-mot-2026'); // l'utilisateur continue de taper
      premiere.complete(http.Response(_reponse(), 200));
      expect(await verification, EtatVerificationMotDePasse.compromis);
      expect(provider.etat, EtatVerificationMotDePasse.idle); // résultat périmé non affiché
    });
  });

  testWidgets('message de compromission puis message d’indisponibilité', (tester) async {
    var serviceEnPanne = false;
    var appels = 0;
    final provider = MotDePasseProvider(
      service: MotDePasseService(
        client: MockClient((_) async {
          appels++;
          return serviceEnPanne ? http.Response('', 503) : http.Response(_reponse(), 200);
        }),
      ),
    );
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider.value(
            value: provider,
            child: Column(
              children: [
                TextField(onChanged: provider.surSaisie),
                const IndicateurMotDePasse(),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'password');
    await tester.pump(const Duration(milliseconds: 100));
    expect(appels, 0, reason: 'aucun appel avant la fin de l’anti-rebond');
    expect(find.textContaining('Force : faible'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(appels, 1);
    expect(
      find.text('Ce mot de passe apparaît dans des fuites de données (9 659 365 fois). Choisissez-en un autre.'),
      findsOneWidget,
    );

    serviceEnPanne = true;
    await tester.enterText(find.byType(TextField), 'Une-phrase-2026');
    await tester.pump();
    expect(find.textContaining('fuites de données ('), findsNothing);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();
    expect(find.text('Vérification des fuites indisponible'), findsOneWidget);
    expect(find.textContaining('Force : fort'), findsOneWidget);
  });
}
