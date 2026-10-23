import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/launcher_settings.dart';
import '../services/crash_diagnoser.dart';
import '../services/launch_service.dart';

class LaunchProvider extends ChangeNotifier {
  LaunchProvider({LaunchService? service})
      : _service = service ?? LaunchService();

  final LaunchService _service;
  bool _launching = false;
  String? _error;
  String? _status;
  int _errorTicket = 0;

  bool get launching => _launching;
  bool get isRunning => _service.isRunning;
  String? get error => _error;
  String? get status => _status;

  /// Increments whenever a new error is produced; the UI listens for
  /// changes to pop an error dialog.
  int get errorTicket => _errorTicket;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<bool> play({
    required Account account,
    required String versionId,
    required LauncherSettings settings,
  }) async {
    _launching = true;
    _error = null;
    _status = 'Starting $versionId...';
    notifyListeners();

    // If the user wants discrete GPU, add the OpenGL flag to JVM args.
    final effectiveJvmArgs = settings.useDiscreteGpu
        ? (settings.jvmArgs.isEmpty
            ? '-Dsun.java2d.opengl=true'
            : '$settings.jvmArgs -Dsun.java2d.opengl=true')
        : settings.jvmArgs;

    final launchSettings = settings.copyWith(jvmArgs: effectiveJvmArgs);

    try {
      await _service.launch(
        account: account,
        versionId: versionId,
        settings: launchSettings,
        onExit: (code, logTail) {
          if (code == 0) {
            // Game exited normally, do not show error dialog
            _error = null;
            notifyListeners();
          } else {
            _status = null;
            final hint = CrashDiagnoser.diagnose(logTail);
            _error = '游戏异常退出（退出码 $code）'
                '${hint.isEmpty ? '' : '\n\n可能的原因：\n$hint'}'
                '${logTail.isEmpty ? '' : '\n\n—— 游戏日志末尾 ——\n$logTail'}';
            _errorTicket++;
            notifyListeners();
          }
        },
      );
      _status = 'Game started';
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _status = null;
      _errorTicket++;
      notifyListeners();
      return false;
    } finally {
      _launching = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _service.stop();
    if (_status != null) {
      _status = 'Stopped';
    }
    notifyListeners();
  }
}
