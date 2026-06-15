import 'package:flutter/foundation.dart';

import '../services/authentication.dart';

class AuthViewModel with ChangeNotifier {
  AuthViewModel({AuthenticationService? authService})
      : _auth = authService ?? AuthenticationService();

  final AuthenticationService _auth;

  bool _isSigningIn = false;
  bool get isSigningIn => _isSigningIn;

  String? _lastError;
  String? get lastError => _lastError;

  String? get currentUid => _auth.currentUid;

  Future<bool> signInWithGitHub() async {
    if (_isSigningIn) return false;
    _isSigningIn = true;
    _lastError = null;
    notifyListeners();
    try {
      final uid = await _auth.logInWithGitHub();
      return uid != null;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  bool _isConnectingGitHub = false;
  bool get isConnectingGitHub => _isConnectingGitHub;

  /// Runs the manual GitHub OAuth connect/reconnect flow to refresh the stored
  /// access token (Android path + the 401 "Reconnect GitHub" action). Returns
  /// true on success; on failure sets [lastError] and returns false. A user
  /// cancelling the browser tab is treated as a (non-error) false.
  Future<bool> connectGitHub() async {
    if (_isConnectingGitHub) return false;
    _isConnectingGitHub = true;
    _lastError = null;
    notifyListeners();
    try {
      return await _auth.connectGitHub();
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _isConnectingGitHub = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.logOut();
    notifyListeners();
  }
}
