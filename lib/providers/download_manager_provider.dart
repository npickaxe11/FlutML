import 'package:flutter/foundation.dart';

import '../models/download_task.dart';

class DownloadManagerProvider extends ChangeNotifier {
  final Map<String, DownloadTask> _tasks = {};
  int _sequence = 0;

  List<DownloadTask> get tasks {
    final list = _tasks.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<DownloadTask> get activeTasks =>
      tasks.where((task) => task.isActive).toList();

  List<DownloadTask> get finishedTasks =>
      tasks.where((task) => !task.isActive).toList();

  int get activeCount => activeTasks.length;

  DownloadTask? task(String id) => _tasks[id];

  String createTask({
    required String title,
    required String subtitle,
    required String kind,
    String stage = '等待中…',
  }) {
    _sequence++;
    final id = '${DateTime.now().microsecondsSinceEpoch}:$_sequence';
    _tasks[id] = DownloadTask(
      id: id,
      title: title,
      subtitle: subtitle,
      kind: kind,
      createdAt: DateTime.now(),
      stage: stage,
      status: DownloadTaskStatus.queued,
    );
    notifyListeners();
    return id;
  }

  void updateTask(
    String id, {
    String? subtitle,
    String? stage,
    int? received,
    int? total,
  }) {
    final current = _tasks[id];
    if (current == null) return;
    _tasks[id] = current.copyWith(
      subtitle: subtitle,
      stage: stage,
      received: received,
      total: total,
      status: DownloadTaskStatus.downloading,
    );
    notifyListeners();
  }

  void completeTask(String id, {String? stage, String? filePath}) {
    final current = _tasks[id];
    if (current == null) return;
    _tasks[id] = current.copyWith(
      stage: stage ?? '已完成',
      received: current.total > 0 ? current.total : current.received,
      status: DownloadTaskStatus.completed,
      filePath: filePath,
    );
    notifyListeners();
  }

  void failTask(String id, Object error) {
    final current = _tasks[id];
    if (current == null) return;
    _tasks[id] = current.copyWith(
      stage: '失败',
      status: DownloadTaskStatus.failed,
      error: error.toString(),
    );
    notifyListeners();
  }

  void removeTask(String id) {
    if (_tasks.remove(id) != null) {
      notifyListeners();
    }
  }

  void clearFinished() {
    _tasks.removeWhere((_, task) => !task.isActive);
    notifyListeners();
  }
}
