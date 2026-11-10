import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studenthub/models/photo_analysis.dart';
import 'package:studenthub/services/gemini_service.dart';

const _url = 'https://serveur.test';

http.Response _json(Object corps, [int statut = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(corps)),
  statut,
  headers: {'content-type': 'application/json'},
);

GeminiService _service(MockClientHandler repondre, {String baseUrl = _url}) =>
    GeminiService(client: MockClient(repondre), baseUrl: baseUrl);

void main() {
  late Directory dossier;
  late File photo;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('gemini_service_test');
    photo = File('${dossier.path}/fuite.jpg');
    await photo.writeAsBytes([1, 2, 3, 4]);
  });

  tearDown(() => dossier.delete(recursive: true));

  Future<void> attendErreur(GeminiService service, String message) =>
      expectLater(
        service.analyserPhoto(photo),
        throwsA(
          isA<GeminiException>().having((e) => e.message, 'message', message),
        ),
      );

  test('succès : envoie la photo en base64 et lit la réponse', () async {
    late http.Request requete;
    final resultat = await _service((r) async {
      requete = r;
      return _json({
        'is_maintenance_issue': true,
        'category': 'plomberie',
        'room': 'cuisine',
        'urgency': 'elevee',
        'title': 'Fuite sous évier',
        'description': 'Une fuite importante sous l’évier de la cuisine.',
      });
    }).analyserPhoto(photo);

    expect(requete.method, 'POST');
    expect(requete.url.toString(), '$_url/maintenance/analyze');
    expect(requete.headers.keys, isNot(contains('x-goog-api-key')));
    final corps = jsonDecode(requete.body) as Map<String, dynamic>;
    expect(corps['imageBase64'], base64Encode([1, 2, 3, 4]));
    expect(corps['mimeType'], 'image/jpeg');
    expect(resultat.isMaintenanceIssue, isTrue);
    expect(resultat.category, 'plomberie');
    expect(resultat.title, 'Fuite sous évier');
  });

  test('le type dépend de l’extension', () async {
    final types = <String>[];
    final service = _service((r) async {
      types.add((jsonDecode(r.body) as Map)['mimeType'] as String);
      return _json({'is_maintenance_issue': false});
    });
    for (final nom in ['a.PNG', 'b.webp', 'c.heic']) {
      final fichier = File('${dossier.path}/$nom');
      await fichier.writeAsBytes([1]);
      await service.analyserPhoto(fichier);
    }
    expect(types, ['image/png', 'image/webp', 'image/jpeg']);
  });

  test('photo hors sujet', () async {
    final resultat = await _service(
      (_) async => _json({
        'is_maintenance_issue': false,
        'category': null,
        'room': null,
        'urgency': null,
        'title': null,
        'description': null,
      }),
    ).analyserPhoto(photo);
    expect(resultat.isMaintenanceIssue, isFalse);
    expect(resultat.title, isNull);
  });

  test('fromJson ignore les valeurs qui ne sont pas du texte', () {
    final resultat = PhotoAnalysis.fromJson({
      'is_maintenance_issue': 'true',
      'category': 12,
      'title': ['x'],
    });
    expect(resultat.isMaintenanceIssue, isFalse);
    expect(resultat.category, isNull);
    expect(resultat.title, isNull);
  });

  final erreurs = {
    413: 'Photo trop lourde. Choisis une image plus légère.',
    415: 'Format non pris en charge. Utilise une photo JPEG, PNG ou WebP.',
    429: "Trop d'analyses pour le moment. Réessaie plus tard.",
    503: 'Analyse IA non configurée sur le serveur. Remplis le formulaire à la main.',
    502: 'Analyse impossible. Réessaie ou remplis le formulaire à la main.',
    500: 'Analyse impossible. Réessaie ou remplis le formulaire à la main.',
  };
  erreurs.forEach((statut, message) {
    test('erreur HTTP $statut', () async {
      await attendErreur(
        _service((_) async => _json({'error': 'x'}, statut)),
        message,
      );
    });
  });

  for (final corps in ['pas du json', '[1, 2]']) {
    test('réponse illisible : $corps', () async {
      await attendErreur(
        _service((_) async => http.Response(corps, 200)),
        'Analyse impossible. Réessaie ou remplis le formulaire à la main.',
      );
    });
  }

  test('fichier introuvable', () async {
    await expectLater(
      _service(
        (_) async => _json({}),
      ).analyserPhoto(File('${dossier.path}/absente.jpg')),
      throwsA(isA<GeminiException>()),
    );
  });

  test('réseau coupé', () async {
    await attendErreur(
      _service((_) async => throw http.ClientException('coupé')),
      'Serveur injoignable. Tu peux remplir le formulaire à la main.',
    );
    await attendErreur(
      _service((_) async => throw const SocketException('coupé')),
      'Serveur injoignable. Tu peux remplir le formulaire à la main.',
    );
  });

  test('URL absente : aucun appel réseau', () async {
    var appels = 0;
    await attendErreur(
      _service((_) async {
        appels++;
        return _json({});
      }, baseUrl: '  '),
      'Analyse IA non configurée. Remplis le formulaire à la main.',
    );
    expect(appels, 0);
  });

  for (final url in [
    'http://serveur.test',
    'http://10.0.2.2:6500',
    'ftp://serveur.test',
    'nimporte quoi',
  ]) {
    test('URL refusée sans autorisation explicite : $url', () async {
      await attendErreur(
        _service((_) async => _json({}), baseUrl: url),
        'Adresse du serveur invalide. Remplis le formulaire à la main.',
      );
    });
  }
}
