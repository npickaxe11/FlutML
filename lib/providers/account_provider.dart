import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../services/auth_service.dart';
import '../services/auth_models.dart';
import '../services/authlib_service.dart';
import '../services/microsoft_auth_service.dart';

class AccountProvider extends ChangeNotifier {
  AccountProvider({
    AuthService? authService,
    MicrosoftAuthService? microsoftAuth,
    AuthlibService? authlib,
  })  : _auth = authService ?? AuthService(),
        _microsoft = microsoftAuth ?? MicrosoftAuthService(),
        _authlib = authlib ?? AuthlibService();

  final AuthService _auth;
  final MicrosoftAuthService _microsoft;
  final AuthlibService _authlib;

  Account? _account;
  bool _loading = true;
  String? _error;
  bool _msaBusy = false;
  DeviceCodeStart? _deviceCode;

  Account? get account => _account;
  bool get isLoggedIn => _account != null;
  bool get loading => _loading;
  String? get error => _error;
  bool get msaBusy => _msaBusy;
  DeviceCodeStart? get deviceCode => _deviceCode;

  Future<void> init() async {
    _loading = true;
    notifyListeners();
    try {
      _account = await _auth.loadAccount();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> loginOffline(String username) async {
    _error = null;
    try {
      _account = await _auth.loginOffline(username);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Invalid argument(s): ', '');
      notifyListeners();
      return false;
    }
  }

  Future<void> startMicrosoftLogin() async {
    _error = null;
    _msaBusy = true;
    _deviceCode = null;
    notifyListeners();
    try {
      _deviceCode = await _microsoft.startDeviceCodeFlow();
    } catch (e) {
      _error = e.toString();
    } finally {
      _msaBusy = false;
      notifyListeners();
    }
  }

  /// Convenience: start the device-code flow and poll until completion.
  Future<bool> startMicrosoftLoginAndPoll({
    void Function(String status)? onStatus,
  }) async {
    await startMicrosoftLogin();
    if (_deviceCode == null) return false;
    return completeMicrosoftLogin(onStatus: onStatus);
  }

  /// Polls the pending device-code flow until the user completes sign-in.
  Future<bool> completeMicrosoftLogin({
    void Function(String status)? onStatus,
  }) async {
    final start = _deviceCode;
    if (start == null || _msaBusy) return false;
    _error = null;
    _msaBusy = true;
    notifyListeners();
    try {
      _account = await _microsoft.pollAndComplete(
        start,
        onStatus: onStatus,
      );
      await _persist(_account!);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _msaBusy = false;
      _deviceCode = null;
      notifyListeners();
    }
  }

  Future<bool> cancelMicrosoftLogin() async {
    if (_deviceCode == null) return true;
    _deviceCode = null;
    _msaBusy = false;
    notifyListeners();
    return true;
  }

  Future<bool> loginSkinServer({
    required String serverUrl,
    required String username,
    required String password,
    required bool preferChinaMirror,
  }) async {
    _error = null;
    try {
      final server = await _authlib.resolveServer(serverUrl);
      _account = await _authlib.login(
        server: server,
        username: username,
        password: password,
      );
      await _persist(_account!);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e is AuthException ? e.message : e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Ensures the current session token is valid; refreshes MSA tokens
  /// when close to expiry. Call before launching the game.
  Future<Account?> ensureValidToken({bool preferChinaMirror = false}) async {
    final current = _account;
    if (current == null) return null;
    if (!current.tokenExpired) return current;

    switch (current.type) {
      case AccountType.offline:
        return current;
      case AccountType.msa:
        try {
          _account = await _microsoft.refreshAccount(current);
          await _persist(_account!);
          notifyListeners();
          return _account;
        } catch (e) {
          _error = 'Session expired, please sign in again (${e.toString()})';
          notifyListeners();
          return null;
        }
      case AccountType.authlib:
        // Skin-station tokens are long lived; refresh by re-login would need
        // the raw password, so keep using the stored one.
        return current;
    }
  }

  /// Downloads/caches the authlib-injector agent jar when needed.
  Future<String?> ensureAgentJar({bool preferChinaMirror = false}) async {
    try {
      return await _authlib.ensureAgentJar(preferChinaMirror: preferChinaMirror);
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    await _auth.logout();
    _account = null;
    notifyListeners();
  }

  Future<void> _persist(Account account) => _auth.saveAccount(account);
}
