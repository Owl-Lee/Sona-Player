const cloudRecycleRetention = Duration(days: 30);

DateTime? cloudDeletedAt(Map<String, dynamic> row) {
  final value = row['deleted_at'];
  if (value is DateTime) return value.toUtc();
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

bool isCloudTrackDeleted(Map<String, dynamic> row) =>
    cloudDeletedAt(row) != null;

bool isCloudTrackRecycleExpired(Map<String, dynamic> row, {DateTime? now}) {
  final deletedAt = cloudDeletedAt(row);
  if (deletedAt == null) return false;
  final reference = (now ?? DateTime.now()).toUtc();
  return !deletedAt.add(cloudRecycleRetention).isAfter(reference);
}

List<Map<String, dynamic>> activeCloudTrackRows(
  Iterable<Map<String, dynamic>> rows,
) => rows.where((row) => !isCloudTrackDeleted(row)).toList(growable: false);

List<Map<String, dynamic>> recycledCloudTrackRows(
  Iterable<Map<String, dynamic>> rows,
) => rows.where(isCloudTrackDeleted).toList(growable: false);

List<Map<String, dynamic>> recoverableCloudTrackRows(
  Iterable<Map<String, dynamic>> rows, {
  DateTime? now,
}) => rows
    .where(
      (row) =>
          isCloudTrackDeleted(row) &&
          !isCloudTrackRecycleExpired(row, now: now),
    )
    .toList(growable: false);

List<Map<String, dynamic>> expiredCloudTrackRows(
  Iterable<Map<String, dynamic>> rows, {
  DateTime? now,
}) => rows
    .where((row) => isCloudTrackRecycleExpired(row, now: now))
    .toList(growable: false);
