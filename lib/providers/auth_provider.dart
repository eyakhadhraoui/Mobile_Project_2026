import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? service}) : _service = service ?? AuthService() {
    _subscription = _service.authStateChanges.listen((userId) {
      _currentUserId = userId;
      notifyListeners();
    });
    _loadSession();
  }

  final AuthService _service;
  StreamSubscription<String?>? _subscription;
  String? _currentUserId;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _error;

  String? get currentUserId => _currentUserId;
  bool get isAuthenticated => _currentUserId != null;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get error => _error;

  Future<void> _loadSession() async {
    try {
      _currentUserId = await _service.getCurrentUserId();
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> signIn(String emailOrPhone, String password) async {
    await _run(
      () => _service.signIn(emailOrPhone: emailOrPhone, password: password),
    );
    _currentUserId = await _service.getCurrentUserId();
    notifyListeners();
  }

  Future<void> register({
    required UserModel user,
    required String password,
  }) async {
    await _run(() async {
      await _service.register(user: user, password: password);
    });
    _currentUserId = user.id;
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> resetPassword(String email) async {
    await _run(() => _service.sendPasswordResetEmail(email));
  }

  Future<void> markEmailVerified(String userId) => _service.markEmailVerified(userId);

  Future<UserModel?> getUserByEmail(String email) => _service.getUserByEmail(email);

  Future<List<UserModel>> getUsersForAdministration() => _service.getUsersForAdministration();

  Future<void> setAccountStatus(String userId, AccountStatus status) async {
    await _service.setAccountStatus(userId, status);
    if (_currentUserId == userId && status == AccountStatus.blocked) {
      _currentUserId = null;
      notifyListeners();
    }
  }

  Future<void> signOut() => _run(_service.signOut);

  Future<void> deleteAccount() => _run(_service.deleteAccount);

  Future<void> _run(Future<void> Function() action) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
