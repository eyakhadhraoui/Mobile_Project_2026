import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants/api_constants.dart';

/// Notifications de publication des annonces programmées.
abstract class NotificationsPublication {
  Future<void> initialiser();

  /// Demande l'autorisation d'afficher des notifications et, sur Android 12+,
  /// celle des alarmes exactes. Retourne false si les notifications sont refusées :
  /// l'annonce sera quand même publiée (serveur et rattrapage au démarrage).
  Future<bool> demanderPermissions();

  /// Programme (ou reprogramme) la notification de [annonceId] à [date].
  Future<void> programmer({
    required String annonceId,
    required String titre,
    required DateTime date,
    bool enValidation = false,
  });

  Future<void> annuler(String annonceId);

  Future<void> annulerTout();
}

/// Implémentation sans effet : tests et plateformes sans notifications.
class AucuneNotification implements NotificationsPublication {
  const AucuneNotification();
  @override
  Future<void> initialiser() async {}
  @override
  Future<bool> demanderPermissions() async => false;
  @override
  Future<void> programmer({required String annonceId, required String titre, required DateTime date, bool enValidation = false}) async {}
  @override
  Future<void> annuler(String annonceId) async {}
  @override
  Future<void> annulerTout() async {}
}

/// Notifications locales planifiées avec `zonedSchedule` à l'heure exacte.
class NotificationsLocales implements NotificationsPublication {
  NotificationsLocales._();

  static final NotificationsLocales instance = NotificationsLocales._();

  static const _canal = AndroidNotificationDetails(
    'publication_annonces',
    'Publication des annonces',
    channelDescription: 'Prévient quand une annonce programmée est publiée.',
    importance: Importance.high,
    priority: Priority.high,
  );

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialisation;

  bool get _supporte => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> initialiser() => _initialisation ??= _initialiser();

  Future<void> _initialiser() async {
    if (!_supporte) return;
    tzdata.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // Fuseau du téléphone inconnu : on prend celui de l'application.
      tz.setLocalLocation(tz.getLocation(ApiConstants.fuseauHoraire));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<bool> demanderPermissions() async {
    if (!_supporte) return false;
    try {
      await initialiser();
      final android = _android;
      if (android != null) {
        // Android 13+ : fenêtre système « Autoriser les notifications ».
        final notifications = await android.requestNotificationsPermission() ?? false;
        // Android 12+ : alarmes exactes (ouvre les réglages si nécessaire).
        if (notifications && !(await android.canScheduleExactNotifications() ?? false)) {
          await android.requestExactAlarmsPermission();
        }
        return notifications;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    } on PlatformException catch (error) {
      debugPrint('Permissions de notification : ${error.message}');
      return false;
    }
  }

  @override
  Future<void> programmer({
    required String annonceId,
    required String titre,
    required DateTime date,
    bool enValidation = false,
  }) async {
    if (!_supporte || !date.isAfter(DateTime.now())) return;
    await initialiser();
    final exactes = await _android?.canScheduleExactNotifications() ?? true;
    Future<void> planifier(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: idNotification(annonceId),
      scheduledDate: tz.TZDateTime.from(date, tz.local),
      notificationDetails: const NotificationDetails(android: _canal, iOS: DarwinNotificationDetails()),
      androidScheduleMode: mode,
      title: 'Annonce publiée',
      body: enValidation
          ? 'Votre annonce « $titre » vient d’être envoyée en validation'
          : 'Votre annonce « $titre » vient d’être publiée',
      payload: annonceId,
    );
    try {
      await planifier(exactes ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle);
    } on PlatformException catch (error) {
      // Alarmes exactes refusées entre-temps : notification approximative ;
      // la publication elle-même ne dépend pas de la notification.
      debugPrint('Notification exacte impossible (${error.code}) : mode approximatif.');
      await planifier(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  @override
  Future<void> annuler(String annonceId) async {
    if (!_supporte) return;
    await initialiser();
    await _plugin.cancel(id: idNotification(annonceId));
  }

  @override
  Future<void> annulerTout() async {
    if (!_supporte) return;
    await initialiser();
    await _plugin.cancelAllPendingNotifications();
  }
}

/// Identifiant de notification stable dérivé de l'identifiant d'annonce
/// (hachage FNV-1a sur 31 bits ; String.hashCode n'est pas garanti stable).
int idNotification(String annonceId) {
  var hash = 0x811c9dc5;
  for (final unite in annonceId.codeUnits) {
    hash ^= unite;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
