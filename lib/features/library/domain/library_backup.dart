enum LibraryBackupKind { manual, automatic }

class LibraryBackupEntry {
  const LibraryBackupEntry({
    required this.archivePath,
    required this.size,
    required this.sha256,
    required this.roles,
    required this.originalPaths,
  });

  final String archivePath;
  final int size;
  final String sha256;
  final List<String> roles;
  final List<String> originalPaths;

  Map<String, Object?> toJson() => {
    'path': archivePath,
    'size': size,
    'sha256': sha256,
    'roles': roles,
    'original_paths': originalPaths,
  };

  factory LibraryBackupEntry.fromJson(Map<String, Object?> json) {
    return LibraryBackupEntry(
      archivePath: json['path'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? -1,
      sha256: json['sha256'] as String? ?? '',
      roles: (json['roles'] as List? ?? const <Object>[])
          .whereType<String>()
          .toList(growable: false),
      originalPaths: (json['original_paths'] as List? ?? const <Object>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class LibraryBackupManifest {
  const LibraryBackupManifest({
    required this.formatVersion,
    required this.backupId,
    required this.createdAt,
    required this.appVersion,
    required this.kind,
    required this.entries,
    required this.missingReferences,
  });

  final int formatVersion;
  final String backupId;
  final DateTime createdAt;
  final String appVersion;
  final LibraryBackupKind kind;
  final List<LibraryBackupEntry> entries;
  final List<String> missingReferences;

  int get totalBytes => entries.fold(0, (sum, item) => sum + item.size);

  Map<String, Object?> toJson() => {
    'format_version': formatVersion,
    'backup_id': backupId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'app_version': appVersion,
    'kind': kind.name,
    'entries': entries.map((item) => item.toJson()).toList(growable: false),
    'missing_references': missingReferences,
  };

  factory LibraryBackupManifest.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'] as String?;
    final kind = LibraryBackupKind.values.where(
      (item) => item.name == kindName,
    );
    if (kind.length != 1) {
      throw const FormatException('backup_manifest_invalid_kind');
    }
    return LibraryBackupManifest(
      formatVersion: (json['format_version'] as num?)?.toInt() ?? 0,
      backupId: json['backup_id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      appVersion: json['app_version'] as String? ?? '',
      kind: kind.single,
      entries: (json['entries'] as List? ?? const <Object>[])
          .whereType<Map>()
          .map(
            (item) =>
                LibraryBackupEntry.fromJson(Map<String, Object?>.from(item)),
          )
          .toList(growable: false),
      missingReferences:
          (json['missing_references'] as List? ?? const <Object>[])
              .whereType<String>()
              .toList(growable: false),
    );
  }
}

class LibraryBackupResult {
  const LibraryBackupResult({required this.path, required this.manifest});

  final String path;
  final LibraryBackupManifest manifest;
}

class LibraryBackupExportResult {
  const LibraryBackupExportResult({
    required this.manifest,
    required this.displayName,
    required this.externalLocation,
  });

  final LibraryBackupManifest manifest;

  /// User-visible name returned by the operating-system document provider.
  final String displayName;

  /// An opaque platform location (for example an Android `content://` URI).
  /// It must not be treated as a normal Dart filesystem path.
  final String externalLocation;
}

class LibraryRestorePreparation {
  const LibraryRestorePreparation({
    required this.manifest,
    required this.restartRequired,
  });

  final LibraryBackupManifest manifest;
  final bool restartRequired;
}

class PendingLibraryRestoreStatus {
  const PendingLibraryRestoreStatus({
    required this.lastErrorCode,
    required this.lastFailureAt,
  });

  /// Empty for a freshly staged restore that has not failed at cold start.
  final String lastErrorCode;
  final DateTime? lastFailureAt;

  /// Compatibility alias for callers written before failure codes were
  /// separated from localized presentation text.
  String get lastError => lastErrorCode;

  bool get hasFailed => lastErrorCode.isNotEmpty;
}

class LibraryBackupException implements Exception {
  const LibraryBackupException(this.code, {this.arguments = const {}});

  /// Stable, locale-independent code suitable for persistence and UI lookup.
  final String code;
  final Map<String, String> arguments;

  /// Kept as a compatibility alias for existing logs and callers.
  String get message => code;

  @override
  String toString() => 'LibraryBackupException: $code';
}

class ReferencedLibraryFile {
  const ReferencedLibraryFile({required this.path, required this.roles});

  final String path;
  final Set<String> roles;
}
