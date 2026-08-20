String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;
    return '$hours:${restMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
  final megabytes = kilobytes / 1024;
  if (megabytes < 1024) return '${megabytes.toStringAsFixed(1)} MB';
  final gigabytes = megabytes / 1024;
  return '${gigabytes.toStringAsFixed(2)} GB';
}

String compactCount(int value) {
  if (value < 1000) return '$value';
  return '${(value / 1000).toStringAsFixed(value < 10000 ? 1 : 0)}k';
}
