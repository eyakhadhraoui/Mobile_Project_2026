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
      _currentUserId = await _service.restoreSession();
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
    required String verificationToken,
  }) async {
    await _run(() async {
      await _service.register(
        user: user,
        password: password,
        verificationToken: verificationToken,
      );
    });
    _isInitialized = true;
    notifyListeners();
  }

  /// Crée le compte serveur d'un compte local existant puis ouvre la session.
  Future<void> linkRemoteAccount({
    required String email,
    required String password,
    required String verificationToken,
  }) async {
    await _run(
      () => _service.linkRemoteAccount(
        email: email,
        password: password,
        verificationToken: verificationToken,
      ),
    );
    _currentUserId = await _service.getCurrentUserId();
    notifyListeners();
  }

  /// Retourne false si seul le mot de passe local a pu être changé (hors ligne).
  Future<bool> changePassword({required String ancien, required String nouveau}) async {
    var serveurAJour = false;
    await _run(() async {
      serveurAJour = await _service.changePassword(ancien: ancien, nouveau: nouveau);
    });
    return serveurAJour;
  }

  Future<void> reinitialiserMotDePasse({
    required String email,
    required String nouveau,
    required String verificationToken,
  }) => _run(
    () => _service.reinitialiserMotDePasse(
      email: email,
      nouveau: nouveau,
      verificationToken: verificationToken,
    ),
  );

  Future<void> markEmailVerified(String userId) => _service.markEmailVerified(userId);

  Future<UserModel?> getUserByEmail(String email) => _service.getUserByEmail(email);

  Future<List<UserModel>> getUsersForAdministration() => _service.getUsersForAdministration();

  Future<void> setAccountStatus(String userId, AccountStatus status) =>
      _service.setAccountStatus(userId, status);

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
