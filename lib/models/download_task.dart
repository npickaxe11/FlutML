enum DownloadTaskStatus { queued, downloading, completed, failed }

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.createdAt,
    this.stage = '',
    this.received = 0,
    this.total = 0,
    this.status = DownloadTaskStatus.queued,
    this.error,
    this.filePath,
  });

  final String id;
  final String title;
  final String subtitle;
  final String kind;
  final DateTime createdAt;
  final String stage;
  final int received;
  final int total;
  final DownloadTaskStatus status;
  final String? error;
  final String? filePath;

  double? get fraction {
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }

  bool get isActive =>
      status == DownloadTaskStatus.queued ||
      status == DownloadTaskStatus.downloading;

  DownloadTask copyWith({
    String? subtitle,
    String? stage,
    int? received,
    int? total,
    DownloadTaskStatus? status,
    String? error,
    String? filePath,
  }) {
    return DownloadTask(
      id: id,
      title: title,
      subtitle: subtitle ?? this.subtitle,
      kind: kind,
      createdAt: createdAt,
      stage: stage ?? this.stage,
      received: received ?? this.received,
      total: total ?? this.total,
      status: status ?? this.status,
      error: error ?? this.error,
      filePath: filePath ?? this.filePath,
    );
  }
}
