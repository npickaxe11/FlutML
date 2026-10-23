class DownloadProgress {
  const DownloadProgress({
    required this.stage,
    required this.current,
    required this.total,
    this.currentFile = '',
    this.done = false,
    this.error,
  });

  final String stage;
  final int current;
  final int total;
  final String currentFile;
  final bool done;
  final String? error;

  double get fraction {
    if (total <= 0) return 0;
    return (current / total).clamp(0.0, 1.0);
  }

  DownloadProgress copyWith({
    String? stage,
    int? current,
    int? total,
    String? currentFile,
    bool? done,
    String? error,
  }) {
    return DownloadProgress(
      stage: stage ?? this.stage,
      current: current ?? this.current,
      total: total ?? this.total,
      currentFile: currentFile ?? this.currentFile,
      done: done ?? this.done,
      error: error,
    );
  }
}
