import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/user_service.dart';

class UserProvider extends ChangeNotifier {
  UserProvider({UserService? service}) : _service = service ?? UserService();

  final UserService _service;
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
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
