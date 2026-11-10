import 'package:flutter/foundation.dart';
import '../models/notification_covoiturage.dart';
import '../services/notification_covoiturage_service.dart';
class NotificationCovoiturageProvider extends ChangeNotifier {
  NotificationCovoiturageProvider({NotificationCovoiturageService? service}) : _service = service ?? NotificationCovoiturageService();
  final NotificationCovoiturageService _service; List<NotificationCovoiturage> _notifications = []; int _nonLues = 0;
  List<NotificationCovoiturage> get notifications => _notifications; int get nonLues => _nonLues;
  Future<void> charger(String? userId) async { if (userId == null) return; _notifications = await _service.pourUtilisateur(userId); _nonLues = await _service.nonLues(userId); notifyListeners(); }
  Future<void> lire(String id, String userId) async { await _service.lire(id); await charger(userId); }
  Future<void> toutLire(String userId) async { await _service.toutLire(userId); await charger(userId); }
}
