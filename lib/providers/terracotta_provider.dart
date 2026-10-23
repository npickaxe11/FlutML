import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/terracotta_service.dart';

class TerracottaProvider extends ChangeNotifier {
  TerracottaProvider({TerracottaService? service})
    : _service = service ?? TerracottaService();

  final TerracottaService _service;

  bool _starting = false;
  String _state = 'waiting';
  String _roomCode = '';
  String _guestUrl = '';
  int _exceptionType = -1;
  List<dynamic> _profiles = [];
  String? _errorMessage; // 👈 新增：用来存放启动错误
  Timer? _pollTimer;

  bool get starting => _starting;
  bool get isRunning => _service.isRunning;
  String get state => _state;
  String get roomCode => _roomCode;
  String get guestUrl => _guestUrl;
  int get exceptionType => _exceptionType;
  List<dynamic> get profiles => _profiles;
  String? get errorMessage => _errorMessage; // 👈 新增 getter

  Future<void> startEngine({String? playerName}) async {
    _starting = true;
    _errorMessage = null; // 重置错误
    notifyListeners();
    try {
      await _service.start();
      _startPolling(playerName);
    } catch (e) {
      _state = 'exception';
      _exceptionType = -99;
      _errorMessage = e.toString(); // 👈 捕获具体报错
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> shutdown() async {
    _pollTimer?.cancel();
    await _service.stop();
    _state = 'waiting';
    _roomCode = '';
    _guestUrl = '';
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> createRoom({String? playerName}) async {
    await _service.setWaiting();
    await _service.setScanning(player: playerName);
  }

  Future<bool> joinRoom(String code, {String? playerName}) async {
    return await _service.setGuesting(room: code, player: playerName);
  }

  Future<void> leaveRoom() async {
    await _service.setWaiting();
  }

  void _startPolling(String? playerName) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (!isRunning) return;
      final data = await _service.getState();
      if (data.isEmpty) return;

      bool changed = false;
      final newState = data['state'] as String? ?? 'waiting';
      if (_state != newState) {
        _state = newState;
        changed = true;
      }

      if (data['room'] != null && _roomCode != data['room']) {
        _roomCode = data['room'];
        changed = true;
      }
      if (data['url'] != null && _guestUrl != data['url']) {
        _guestUrl = data['url'];
        changed = true;
      }
      if (data['type'] != null) {
        _exceptionType = data['type'];
        changed = true;
      }
      if (data['profiles'] != null) {
        _profiles = data['profiles'] as List<dynamic>;
        changed = true;
      }

      if (changed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _service.stop();
    super.dispose();
  }
}
