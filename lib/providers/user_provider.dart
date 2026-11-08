import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/api_client.dart';
import '../services/user_service.dart';

class UserProvider extends ChangeNotifier {
  UserProvider({UserService? service, ApiClient? api})
    : _service = service ?? UserService(),
      _api = api ?? ApiClient();

  final UserService _service;
  final ApiClient _api;
  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> load(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _user = await _service.getById(userId);
    } catch (error) {
      _error = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> save(UserModel user) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _service.save(user);
      _user = user;
      // Le nom affiché sur les annonces vient du serveur : synchronisation
      // best-effort (le profil local reste enregistré même hors ligne).
      _api.put('/me', {'prenom': user.prenom, 'nom': user.nom}).catchError((_) => null);
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
