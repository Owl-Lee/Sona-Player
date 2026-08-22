import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/serialized_task_queue.dart';
import '../domain/library_backup.dart';
import 'library_database.dart';

final libraryBackupServiceProvider = Provider<LibraryBackupService>((ref) {
  return LibraryBackupService(database: ref.watch(libraryDatabaseProvider));
});

const _formatVersion = 1;
const _applicationVersion = '0.5.0';
const _maxEntries = 100000;
const _maxPathBytes = 16 * 1024;
const _maxJsonBytes = 32 * 1024 * 1024;
const _maxEntryBytes = 1 << 40; // 1 TiB safety boundary, not an allocation.
const _magic = <int>[0x53, 0x4F, 0x4E, 0x41, 0x42, 0x4B, 0x30, 0x31];
const _trailer = <int>[0x53, 0x4F, 0x4E, 0x41, 0x45, 0x4E, 0x44, 0x31];
const _backupDocumentChannel = MethodChannel(
  'com.sonarvault.sona/backup_documents',
);

/// Creates and restores a single-file, self-contained Sona library backup.
///
/// The format is deliberately sequential. Media is copied and hashed in small
/// chunks, so a multi-gigabyte library does not need to fit in memory. Restore
/// always extracts into a private staging directory, verifies every hash and
/// the manifest, rewrites database paths, and only then queues an atomic
/// database replacement for the next cold start.
class LibraryBackupService {
  LibraryBackupService({
    required this.database,
    Directory? applicationSupportDirectory,
    DateTime Function()? clock,
    this.appVersion = _applicationVersion,
  }) : _supportDirectory = applicationSupportDirectory,
       _clock = clock ?? DateTime.now;

  final LibraryDatabase database;
  final Directory? _supportDirectory;
  final DateTime Function() _clock;
  final String appVersion;
  final _backupTasks = SerializedTaskQueue();
  final _restoreTasks = SerializedTaskQueue();
  bool _systemPickerBusy = false;

  Future<Directory> get _support async =>
      _supportDirectory ?? await getApplicationSupportDirectory();

  Future<Directory> get _dataRoot async {
    final support = await _support;
    return Directory(path_util.join(support.path, 'SonarVault'));
  }

  Future<LibraryBackupResult> createBackup({
    required String destinationPath,
    LibraryBackupKind kind = LibraryBackupKind.manual,
  }) {
    return _backupTasks.run(
      () => _createBackup(destinationPath: destinationPath, kind: kind),
    );
  }

  Future<LibraryBackupResult> _createBackup({
    required String destinationPath,
    required LibraryBackupKind kind,
  }) async {
    if (destinationPath.trim().isEmpty) {
      throw const LibraryBackupException('backup_path_empty');
    }
    final destination = File(destinationPath);
    if (_sameFilePath(destination.path, database.databasePath)) {
      throw const LibraryBackupException('backup_would_overwrite_database');
    }
    await destination.parent.create(recursive: true);
    final partial = File('$destinationPath.partial');
    if (await partial.exists()) await partial.delete();

    final root = await _dataRoot;
    await root.create(recursive: true);
    final scratch = Directory(path_util.join(root.path, 'backup_staging'));
    await scratch.create(recursive: true);
    final backupId = _newId('backup');
    final databaseSnapshot = File(
      path_util.join(scratch.path, '$backupId.sqlite'),
    );
    RandomAccessFile? output;
    try {
      await database.createConsistentSnapshot(databaseSnapshot.path);

      // Resolve external files from the snapshot rather than the still-live
      // database. A track imported or deleted during backup therefore cannot
      // make the manifest disagree with the database image being archived.
      final allReferenced = await _readSnapshotReferences(databaseSnapshot);
      // Manual exports are self-contained and therefore include every song and
      // MV. Automatic recovery points intentionally stay lightweight: copying
      // an entire large library several times a day would consume gigabytes of
      // private storage and compete with playback. They retain the consistent
      // database plus managed visual assets; media paths continue to reference
      // the files already present on this device.
      final referenced = kind == LibraryBackupKind.manual
          ? allReferenced
          : allReferenced
                .where(
                  (reference) =>
                      !reference.roles.contains('track_media') &&
                      !reference.roles.contains('track_video'),
                )
                .toList(growable: false);
      if (referenced.any(
        (reference) => _sameFilePath(reference.path, destination.path),
      )) {
        throw const LibraryBackupException(
          'backup_would_overwrite_referenced_file',
        );
      }
      final missing = <String>[];
      final sources = <_BackupSource>[
        _BackupSource(
          file: databaseSnapshot,
          archivePath: 'database/sonar_vault.db',
          roles: const {'database'},
          originalPaths: const [],
        ),
      ];
      var index = 0;
      for (final reference in referenced) {
        final file = File(reference.path);
        if (!await file.exists()) {
          missing.add(reference.path);
          continue;
        }
        final extension = _safeExtension(reference.path);
        sources.add(
          _BackupSource(
            file: file,
            archivePath: 'files/${index.toString().padLeft(6, '0')}$extension',
            roles: reference.roles,
            originalPaths: [reference.path],
          ),
        );
        index++;
      }

      // Never publish a package which advertises references it did not store.
      // Besides songs and paired MVs, artwork, playlist covers and custom
      // backgrounds are part of the portable/manual contract. Automatic
      // backups deliberately omit track media above, but every reference they
      // do elect to package must still be present. Otherwise creation appears
      // successful while the same package is rejected at restore time.
      if (missing.isNotEmpty) {
        throw LibraryBackupException(
          'backup_required_files_missing',
          arguments: {'count': '${missing.length}'},
        );
      }

      final createdAt = _clock().toUtc();
      final header = utf8.encode(
        jsonEncode({
          'backup_id': backupId,
          'created_at': createdAt.toIso8601String(),
        }),
      );
      if (header.length > _maxJsonBytes) {
        throw const LibraryBackupException('backup_header_too_large');
      }

      output = await partial.open(mode: FileMode.write);
      await output.writeFrom(_magic);
      await output.writeFrom(_u32(_formatVersion));
      await output.writeFrom(_u32(sources.length));
      await output.writeFrom(_u32(header.length));
      await output.writeFrom(header);

      final manifestEntries = <LibraryBackupEntry>[];
      for (final source in sources) {
        if (!_isSafeArchivePath(source.archivePath)) {
          throw LibraryBackupException(
            'backup_internal_path_unsafe',
            arguments: {'path': source.archivePath},
          );
        }
        final pathBytes = utf8.encode(source.archivePath);
        final size = await source.file.length();
        await output.writeFrom(_u32(pathBytes.length));
        await output.writeFrom(pathBytes);
        await output.writeFrom(_u64(size));
        final contentStart = await output.position();
        final digest = await _copyAndHash(source.file, output);
        if (await output.position() - contentStart != size) {
          throw LibraryBackupException(
            'backup_source_changed',
            arguments: {'path': source.file.path},
          );
        }
        await output.writeFrom(digest.bytes);
        manifestEntries.add(
          LibraryBackupEntry(
            archivePath: source.archivePath,
            size: size,
            sha256: digest.toString(),
            roles: source.roles.toList()..sort(),
            originalPaths: source.originalPaths,
          ),
        );
      }

      final manifest = LibraryBackupManifest(
        formatVersion: _formatVersion,
        backupId: backupId,
        createdAt: createdAt,
        appVersion: appVersion,
        kind: kind,
        entries: manifestEntries,
        missingReferences: missing..sort(),
      );
      final manifestBytes = utf8.encode(jsonEncode(manifest.toJson()));
      if (manifestBytes.length > _maxJsonBytes) {
        throw const LibraryBackupException('backup_manifest_too_large');
      }
      await output.writeFrom(_u64(manifestBytes.length));
      await output.writeFrom(manifestBytes);
      await output.writeFrom(sha256.convert(manifestBytes).bytes);
      await output.writeFrom(_trailer);
      await output.flush();
      await output.close();
      output = null;

      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
      return LibraryBackupResult(path: destination.path, manifest: manifest);
    } catch (error) {
      await output?.close();
      if (await partial.exists()) await partial.delete();
      if (error is LibraryBackupException) rethrow;
      throw LibraryBackupException(
        'backup_create_failed',
        arguments: {'cause': '$error'},
      );
    } finally {
      if (await databaseSnapshot.exists()) await databaseSnapshot.delete();
    }
  }

  Future<List<ReferencedLibraryFile>> _readSnapshotReferences(
    File databaseSnapshot,
  ) async {
    final snapshotDatabase = LibraryDatabase();
    await snapshotDatabase.initialize(databasePath: databaseSnapshot.path);
    try {
      return await snapshotDatabase.getReferencedLibraryFiles();
    } finally {
      await snapshotDatabase.close();
    }
  }

  Future<LibraryBackupManifest> inspectBackup(String backupPath) async {
    final staging = await Directory.systemTemp.createTemp('sona-inspect-');
    try {
      return await _readAndVerify(File(backupPath), staging, extract: false);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// Creates a backup and streams it to an Android Storage Access Framework
  /// destination selected by the user.
  ///
  /// The package is first written to app-private storage, then copied by the
  /// Android host with a fixed-size buffer. No backup-sized byte array crosses
  /// the method channel or enters the Dart heap. Returning `null` means the
  /// system picker was cancelled.
  ///
  /// Windows presentation code should instead obtain a normal filesystem path
  /// (for example with `FilePicker.saveFile`) and pass it to [createBackup].
  Future<LibraryBackupExportResult?> exportBackupWithSystemPicker({
    String? suggestedFileName,
  }) async {
    _requireAndroidDocumentPicker();
    if (_systemPickerBusy) {
      throw const LibraryBackupException('backup_document_picker_busy');
    }
    _systemPickerBusy = true;

    File? privateBackup;
    try {
      final root = await _dataRoot;
      final staging = Directory(
        path_util.join(root.path, 'backup_staging', 'document_exports'),
      );
      await staging.create(recursive: true);
      final exportId = _newId('export');
      privateBackup = File(
        path_util.join(staging.path, '$exportId.sonabackup'),
      );
      final backup = await createBackup(destinationPath: privateBackup.path);
      final displayName = _safeBackupFileName(suggestedFileName);

      final raw = await _backupDocumentChannel.invokeMethod<Object?>(
        'exportBackupDocument',
        <String, Object?>{
          'sourcePath': privateBackup.path,
          'suggestedName': displayName,
          'mimeType': 'application/vnd.sona.backup',
        },
      );
      if (raw == null) return null;
      if (raw is! Map) {
        throw const LibraryBackupException(
          'backup_document_export_result_invalid',
        );
      }
      final values = Map<Object?, Object?>.from(raw);
      final externalLocation = values['externalLocation'] as String? ?? '';
      final actualDisplayName = values['displayName'] as String? ?? '';
      if (externalLocation.isEmpty || actualDisplayName.isEmpty) {
        throw const LibraryBackupException(
          'backup_document_export_location_missing',
        );
      }
      return LibraryBackupExportResult(
        manifest: backup.manifest,
        displayName: actualDisplayName,
        externalLocation: externalLocation,
      );
    } on PlatformException catch (error) {
      throw LibraryBackupException(
        'backup_document_export_failed',
        arguments: {'platformCode': error.code},
      );
    } on MissingPluginException {
      throw const LibraryBackupException('backup_document_picker_unavailable');
    } finally {
      await _deleteTemporaryFile(privateBackup);
      _systemPickerBusy = false;
    }
  }

  /// Lets the user choose an Android document, streams it into app-private
  /// staging, and fully verifies it before queuing the cold-start restore.
  ///
  /// Returning `null` means the picker was cancelled. On Windows, presentation
  /// code should use a path-only file picker (`withData: false`) and pass the
  /// selected path to [stageRestore].
  Future<LibraryRestorePreparation?>
  pickAndStageRestoreWithSystemPicker() async {
    _requireAndroidDocumentPicker();
    if (_systemPickerBusy) {
      throw const LibraryBackupException('backup_document_picker_busy');
    }
    _systemPickerBusy = true;

    File? importedBackup;
    try {
      final root = await _dataRoot;
      final imports = Directory(path_util.join(root.path, 'restore_imports'));
      await imports.create(recursive: true);
      importedBackup = File(
        path_util.join(imports.path, '${_newId('import')}.sonabackup'),
      );

      final raw = await _backupDocumentChannel.invokeMethod<Object?>(
        'importBackupDocument',
        <String, Object?>{
          'destinationPath': importedBackup.path,
          'mimeTypes': const <String>[
            'application/vnd.sona.backup',
            'application/octet-stream',
          ],
        },
      );
      if (raw == null) return null;
      if (raw is! Map || !await importedBackup.exists()) {
        throw const LibraryBackupException(
          'backup_document_import_result_invalid',
        );
      }
      return await stageRestore(importedBackup.path);
    } on PlatformException catch (error) {
      throw LibraryBackupException(
        'backup_document_import_failed',
        arguments: {'platformCode': error.code},
      );
    } on MissingPluginException {
      throw const LibraryBackupException('backup_document_picker_unavailable');
    } finally {
      await _deleteTemporaryFile(importedBackup);
      _systemPickerBusy = false;
    }
  }

  void _requireAndroidDocumentPicker() {
    if (!Platform.isAndroid) {
      throw const LibraryBackupException('backup_document_picker_android_only');
    }
  }

  String _safeBackupFileName(String? value) {
    final fallbackTimestamp = _clock()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    var name = (value ?? '').trim().replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1f]'),
      '-',
    );
    if (name.isEmpty) name = 'Sona-library-$fallbackTimestamp';
    if (name.length > 120) name = name.substring(0, 120).trimRight();
    if (!name.toLowerCase().endsWith('.sonabackup')) {
      name = '$name.sonabackup';
    }
    return name;
  }

  Future<void> _deleteTemporaryFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A stale private staging file is safe and can be removed by maintenance
      // later. Cleanup must not turn a successful export or staged restore into
      // a user-visible failure.
    }
  }

  Future<bool> hasPendingRestore() async {
    final root = await _dataRoot;
    return File(path_util.join(root.path, 'pending_restore.json')).exists();
  }

  Future<PendingLibraryRestoreStatus?> pendingRestoreStatus() async {
    final root = await _dataRoot;
    final marker = File(path_util.join(root.path, 'pending_restore.json'));
    if (!await marker.exists()) return null;
    final failure = File(
      path_util.join(root.path, 'pending_restore_failure.json'),
    );
    if (!await failure.exists()) {
      return const PendingLibraryRestoreStatus(
        lastErrorCode: '',
        lastFailureAt: null,
      );
    }
    try {
      final values = Map<String, Object?>.from(
        jsonDecode(await failure.readAsString()) as Map,
      );
      return PendingLibraryRestoreStatus(
        lastErrorCode:
            values['code'] as String? ?? values['message'] as String? ?? '',
        lastFailureAt: DateTime.tryParse(values['failed_at'] as String? ?? '')
            ?.toLocal(),
      );
    } catch (_) {
      return const PendingLibraryRestoreStatus(
        lastErrorCode: 'backup_restore_failure_record_corrupt',
        lastFailureAt: null,
      );
    }
  }

  static Future<void> recordPendingRestoreFailure(
    String errorCode, {
    Directory? applicationSupportDirectory,
  }) async {
    final support =
        applicationSupportDirectory ?? await getApplicationSupportDirectory();
    final root = Directory(path_util.join(support.path, 'SonarVault'));
    final marker = File(path_util.join(root.path, 'pending_restore.json'));
    if (!await marker.exists()) return;
    await root.create(recursive: true);
    await _writeJsonAtomically(
      File(path_util.join(root.path, 'pending_restore_failure.json')),
      <String, Object?>{
        'code': errorCode,
        'failed_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  /// Cancels a staged-but-not-yet-applied restore without touching the live
  /// database. This is also the recovery path for a damaged pending marker.
  Future<void> discardPendingRestore() async {
    final root = await _dataRoot;
    final marker = File(path_util.join(root.path, 'pending_restore.json'));
    if (await marker.exists()) {
      try {
        final values = Map<String, Object?>.from(
          jsonDecode(await marker.readAsString()) as Map,
        );
        final assetsPath = values['restored_assets'] as String? ?? '';
        final restoredRoot = Directory(path_util.join(root.path, 'restored'));
        if (_isDescendant(restoredRoot, assetsPath)) {
          final assets = Directory(assetsPath);
          if (await assets.exists()) await assets.delete(recursive: true);
        }
      } catch (_) {
        // A corrupt marker still remains safe to discard. It cannot name a
        // trusted asset directory, so only transient staging is cleaned below.
      }
      await marker.delete();
    }
    final markerPartial = File('${marker.path}.partial');
    if (await markerPartial.exists()) await markerPartial.delete();
    final failure = File(
      path_util.join(root.path, 'pending_restore_failure.json'),
    );
    if (await failure.exists()) await failure.delete();
    final failurePartial = File('${failure.path}.partial');
    if (await failurePartial.exists()) await failurePartial.delete();
    final stagingRoot = Directory(path_util.join(root.path, 'restore_staging'));
    if (await stagingRoot.exists()) await stagingRoot.delete(recursive: true);
  }

  /// Fully verifies and stages a restore. The live database is never touched.
  /// The caller should ask the user to restart after this returns successfully.
  Future<LibraryRestorePreparation> stageRestore(String backupPath) {
    return _restoreTasks.run(
      () => _stageRestore(backupPath, expectedKind: LibraryBackupKind.manual),
    );
  }

  /// Restores one of Sona's lightweight automatic snapshots on the device
  /// which created it. Media is deliberately not imported from the archive:
  /// every song/MV path in the snapshot must still exist on this device.
  Future<LibraryRestorePreparation> stageAutomaticRestore(String backupPath) {
    return _restoreTasks.run(
      () =>
          _stageRestore(backupPath, expectedKind: LibraryBackupKind.automatic),
    );
  }

  Future<LibraryRestorePreparation> _stageRestore(
    String backupPath, {
    required LibraryBackupKind expectedKind,
  }) async {
    final root = await _dataRoot;
    await root.create(recursive: true);
    if (expectedKind == LibraryBackupKind.automatic) {
      final automaticRoot = Directory(
        path_util.join(root.path, 'backups', 'automatic'),
      );
      if (!_isDescendant(automaticRoot, backupPath)) {
        throw const LibraryBackupException(
          'backup_automatic_restore_outside_managed_directory',
        );
      }
    }
    final pendingMarker = File(
      path_util.join(root.path, 'pending_restore.json'),
    );
    if (await pendingMarker.exists()) {
      throw const LibraryBackupException('backup_restore_already_pending');
    }

    final executionId = _newId('restore');
    final staging = Directory(
      path_util.join(root.path, 'restore_staging', executionId),
    );
    await staging.create(recursive: true);
    Directory? finalAssets;
    try {
      final manifest = await _readAndVerify(
        File(backupPath),
        staging,
        extract: true,
      );
      if (manifest.kind != expectedKind) {
        throw LibraryBackupException(
          expectedKind == LibraryBackupKind.manual
              ? 'backup_restore_kind_automatic_not_manual'
              : 'backup_restore_kind_manual_not_automatic',
        );
      }
      if (manifest.missingReferences.isNotEmpty) {
        throw const LibraryBackupException(
          'backup_restore_manifest_has_missing_references',
        );
      }
      final stagedDatabase = File(
        path_util.join(staging.path, 'database', 'sonar_vault.db'),
      );
      if (!await stagedDatabase.exists()) {
        throw const LibraryBackupException('backup_restore_database_missing');
      }

      finalAssets = Directory(
        path_util.join(root.path, 'restored', executionId),
      );
      await finalAssets.create(recursive: true);
      final stagedFiles = Directory(path_util.join(staging.path, 'files'));
      final finalFiles = Directory(path_util.join(finalAssets.path, 'files'));
      if (await stagedFiles.exists()) await stagedFiles.rename(finalFiles.path);

      final replacements = <String, String>{};
      final entriesByRestoredPath = <String, LibraryBackupEntry>{};
      for (final entry in manifest.entries) {
        if (!entry.archivePath.startsWith('files/')) continue;
        final restoredPath = path_util.joinAll([
          finalAssets.path,
          ...entry.archivePath.split('/'),
        ]);
        final restoredKey = _filePathKey(restoredPath);
        if (entriesByRestoredPath.containsKey(restoredKey)) {
          throw const LibraryBackupException(
            'backup_restore_duplicate_asset_destination',
          );
        }
        entriesByRestoredPath[restoredKey] = entry;
        for (final original in entry.originalPaths) {
          replacements[original] = restoredPath;
        }
      }

      final restoredDatabase = LibraryDatabase();
      await restoredDatabase.initialize(databasePath: stagedDatabase.path);
      try {
        await restoredDatabase.rewriteStoredFilePaths(replacements);
        await _validateRestoredReferences(
          restoredDatabase: restoredDatabase,
          manifestKind: expectedKind,
          restoredAssets: finalAssets,
          entriesByRestoredPath: entriesByRestoredPath,
        );
        if (!await restoredDatabase.validateIntegrity()) {
          throw const LibraryBackupException(
            'backup_restore_database_integrity_failed',
          );
        }
      } finally {
        await restoredDatabase.close();
      }

      final marker = {
        'format_version': _formatVersion,
        'backup_id': manifest.backupId,
        'staged_database': stagedDatabase.path,
        'staged_database_sha256': (await _fileSha256(stagedDatabase))
            .toString(),
        'restored_assets': finalAssets.path,
        'prepared_at': _clock().toUtc().toIso8601String(),
      };
      await _writeJsonAtomically(pendingMarker, marker);
      return LibraryRestorePreparation(
        manifest: manifest,
        restartRequired: true,
      );
    } catch (error) {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (finalAssets != null && await finalAssets.exists()) {
        await finalAssets.delete(recursive: true);
      }
      if (error is LibraryBackupException) rethrow;
      throw LibraryBackupException(
        'backup_restore_prepare_failed',
        arguments: {'cause': '$error'},
      );
    }
  }

  Future<void> _validateRestoredReferences({
    required LibraryDatabase restoredDatabase,
    required LibraryBackupKind manifestKind,
    required Directory restoredAssets,
    required Map<String, LibraryBackupEntry> entriesByRestoredPath,
  }) async {
    final references = await restoredDatabase.getReferencedLibraryFiles();
    var unavailableCount = 0;
    var outsidePackageCount = 0;
    var roleMismatchCount = 0;

    for (final reference in references) {
      final file = File(reference.path);
      if (!await file.exists()) {
        unavailableCount++;
        continue;
      }

      final entry = entriesByRestoredPath[_filePathKey(reference.path)];
      if (entry == null) {
        final isLiveAutomaticMedia =
            manifestKind == LibraryBackupKind.automatic &&
            (reference.roles.contains('track_media') ||
                reference.roles.contains('track_video'));
        if (!isLiveAutomaticMedia) outsidePackageCount++;
        continue;
      }

      if (!_isDescendant(restoredAssets, reference.path)) {
        outsidePackageCount++;
        continue;
      }
      final archivedRoles = entry.roles.toSet();
      if (!archivedRoles.containsAll(reference.roles)) roleMismatchCount++;
    }

    if (unavailableCount > 0) {
      throw LibraryBackupException(
        manifestKind == LibraryBackupKind.automatic
            ? 'backup_restore_local_media_missing'
            : 'backup_restore_referenced_file_missing',
        arguments: {'count': '$unavailableCount'},
      );
    }
    if (outsidePackageCount > 0) {
      throw LibraryBackupException(
        'backup_restore_reference_outside_package',
        arguments: {'count': '$outsidePackageCount'},
      );
    }
    if (roleMismatchCount > 0) {
      throw LibraryBackupException(
        'backup_restore_reference_role_mismatch',
        arguments: {'count': '$roleMismatchCount'},
      );
    }
  }

  Future<LibraryBackupResult> createAutomaticBackup({int keep = 3}) async {
    if (keep < 1) throw ArgumentError.value(keep, 'keep');
    final root = await _dataRoot;
    final directory = Directory(
      path_util.join(root.path, 'backups', 'automatic'),
    );
    await directory.create(recursive: true);
    final timestamp = _clock().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final result = await createBackup(
      destinationPath: path_util.join(
        directory.path,
        'sona-auto-$timestamp.sonabackup',
      ),
      kind: LibraryBackupKind.automatic,
    );
    await pruneAutomaticBackups(keep: keep);
    return result;
  }

  Future<List<File>> automaticBackups() async {
    final root = await _dataRoot;
    final directory = Directory(
      path_util.join(root.path, 'backups', 'automatic'),
    );
    if (!await directory.exists()) return const [];
    final files = await directory
        .list(followLinks: false)
        .where(
          (entity) => entity is File && entity.path.endsWith('.sonabackup'),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> pruneAutomaticBackups({int keep = 3}) async {
    final files = await automaticBackups();
    for (final file in files.skip(max(1, keep))) {
      await file.delete();
    }
  }

  /// Applies a previously verified restore before the live database is open.
  /// The previous database is retained as `sonar_vault.pre_restore.db`.
  static Future<bool> applyPendingRestore({
    Directory? applicationSupportDirectory,
    String? databasePath,
  }) async {
    try {
      return await _applyPendingRestore(
        applicationSupportDirectory: applicationSupportDirectory,
        databasePath: databasePath,
      );
    } on LibraryBackupException {
      rethrow;
    } catch (error) {
      // Cold-start recovery is deliberately normalized to the domain error so
      // startup can keep the previous offline library available and leave the
      // marker in place for an explicit retry/discard action.
      throw LibraryBackupException(
        'backup_restore_apply_pending_failed',
        arguments: {'cause': '$error'},
      );
    }
  }

  static Future<bool> _applyPendingRestore({
    Directory? applicationSupportDirectory,
    String? databasePath,
  }) async {
    final support =
        applicationSupportDirectory ?? await getApplicationSupportDirectory();
    final root = Directory(path_util.join(support.path, 'SonarVault'));
    final marker = File(path_util.join(root.path, 'pending_restore.json'));
    final failure = File(
      path_util.join(root.path, 'pending_restore_failure.json'),
    );
    if (!await marker.exists()) {
      if (await failure.exists()) await failure.delete();
      return false;
    }

    Map<String, Object?> values;
    try {
      values = Map<String, Object?>.from(
        jsonDecode(await marker.readAsString()) as Map,
      );
    } catch (_) {
      throw const LibraryBackupException('backup_restore_marker_corrupt');
    }
    final stagedPath = values['staged_database'] as String? ?? '';
    final stagedDatabaseSha256 =
        values['staged_database_sha256'] as String? ?? '';
    final assetsPath = values['restored_assets'] as String? ?? '';
    if (!_isDescendant(root, stagedPath) || !_isDescendant(root, assetsPath)) {
      throw const LibraryBackupException('backup_restore_path_outside_data');
    }
    final staged = File(stagedPath);
    if (!await staged.exists() || !await Directory(assetsPath).exists()) {
      throw const LibraryBackupException('backup_restore_files_incomplete');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(stagedDatabaseSha256) ||
        (await _fileSha256(staged)).toString() != stagedDatabaseSha256) {
      throw const LibraryBackupException('backup_restore_hash_mismatch');
    }

    final verifier = LibraryDatabase();
    await verifier.initialize(databasePath: staged.path);
    try {
      if (!await verifier.validateIntegrity()) {
        throw const LibraryBackupException(
          'backup_restore_pending_database_integrity_failed',
        );
      }
    } finally {
      await verifier.close();
    }

    final target = File(
      databasePath ?? path_util.join(root.path, 'sonar_vault.db'),
    );
    await target.parent.create(recursive: true);
    final replacement = File('${target.path}.restore-new');
    final rollback = File('${target.path}.pre_restore');
    final rollbackPartial = File('${rollback.path}.partial');

    // Recover the only crash window in the two-rename commit: the previous
    // process moved the live DB aside but did not yet install the replacement.
    // Put the old DB back first, then retry from a known-good state.
    if (!await target.exists() && await rollback.exists()) {
      if (await replacement.exists()) await replacement.delete();
      try {
        await rollback.rename(target.path);
      } on FileSystemException catch (error) {
        throw LibraryBackupException(
          'backup_restore_rollback_failed',
          arguments: {'cause': error.message},
        );
      }
    }
    if (await target.exists() && await _filesEqualBySha256(target, staged)) {
      // The process previously committed the replacement but stopped before
      // deleting its marker. Treat replay as success without overwriting the
      // original pre-restore rollback database.
      await marker.delete();
      if (await failure.exists()) await failure.delete();
      final stagingRoot = Directory(
        path_util.dirname(path_util.dirname(staged.path)),
      );
      if (_isDescendant(root, stagingRoot.path) && await stagingRoot.exists()) {
        await stagingRoot.delete(recursive: true);
      }
      return true;
    }
    if (await replacement.exists()) await replacement.delete();
    await _copyFileStreaming(staged, replacement);
    if (!await _filesEqualBySha256(staged, replacement)) {
      await replacement.delete();
      throw const LibraryBackupException('backup_restore_copy_hash_mismatch');
    }
    // A crashed SQLite process can leave committed transactions only in the
    // live database WAL. Deleting sidecars or merely renaming the main file
    // would silently discard those transactions from the retained rollback.
    // VACUUM INTO reads the complete logical database (main file + WAL) and
    // creates a standalone image before the live files are touched.
    if (await rollbackPartial.exists()) await rollbackPartial.delete();
    await _deleteSidecars(rollbackPartial.path);
    if (await target.exists()) {
      await _createConsistentRollbackSnapshot(target, rollbackPartial);
      if (await rollback.exists()) await rollback.delete();
      await _deleteSidecars(rollback.path);
      await rollbackPartial.rename(rollback.path);
    }

    var oldRemoved = false;
    try {
      // Sidecars are safe to remove only after the consistent rollback image
      // above has durably captured their committed pages.
      await _deleteSidecars(target.path);
      if (await target.exists()) {
        await target.delete();
        oldRemoved = true;
      }
      await replacement.rename(target.path);
    } catch (error) {
      if (!await target.exists() && oldRemoved && await rollback.exists()) {
        await rollback.rename(target.path);
      }
      if (await replacement.exists()) await replacement.delete();
      if (error is LibraryBackupException) rethrow;
      throw LibraryBackupException(
        'backup_restore_apply_failed',
        arguments: {'cause': '$error'},
      );
    }

    // Replacement is committed. Cleanup is best-effort and intentionally
    // outside the rollback block: a temporary marker deletion failure must not
    // undo a database which has already been atomically installed.
    try {
      await marker.delete();
      if (await failure.exists()) await failure.delete();
      final stagingRoot = Directory(
        path_util.dirname(path_util.dirname(staged.path)),
      );
      if (_isDescendant(root, stagingRoot.path) && await stagingRoot.exists()) {
        await stagingRoot.delete(recursive: true);
      }
    } on FileSystemException {
      // The next startup detects an already-applied database by SHA-256 and
      // only retries cleanup, preserving the original rollback snapshot.
    }
    return true;
  }

  static Future<void> _createConsistentRollbackSnapshot(
    File source,
    File destination,
  ) async {
    final liveDatabase = LibraryDatabase();
    var liveDatabaseOpened = false;
    try {
      await liveDatabase.initialize(databasePath: source.path);
      liveDatabaseOpened = true;
      if (!await liveDatabase.validateIntegrity()) {
        throw const LibraryBackupException(
          'backup_restore_live_database_integrity_failed',
        );
      }
      await liveDatabase.createConsistentSnapshot(destination.path);
    } finally {
      if (liveDatabaseOpened) await liveDatabase.close();
    }

    final snapshotDatabase = LibraryDatabase();
    var snapshotDatabaseOpened = false;
    try {
      await snapshotDatabase.initialize(databasePath: destination.path);
      snapshotDatabaseOpened = true;
      if (!await snapshotDatabase.validateIntegrity()) {
        throw const LibraryBackupException(
          'backup_restore_rollback_snapshot_integrity_failed',
        );
      }
    } finally {
      if (snapshotDatabaseOpened) await snapshotDatabase.close();
    }
  }

  Future<LibraryBackupManifest> _readAndVerify(
    File backup,
    Directory staging, {
    required bool extract,
  }) async {
    if (!await backup.exists()) {
      throw const LibraryBackupException('backup_file_missing');
    }
    RandomAccessFile? input;
    final extracted = <String, _VerifiedEntry>{};
    try {
      input = await backup.open();
      _expectBytes(await _readExact(input, _magic.length), _magic, 'header');
      final version = _decodeU32(await _readExact(input, 4));
      if (version != _formatVersion) {
        throw LibraryBackupException(
          'backup_version_unsupported',
          arguments: {'version': '$version'},
        );
      }
      final count = _decodeU32(await _readExact(input, 4));
      if (count < 1 || count > _maxEntries) {
        throw const LibraryBackupException('backup_entry_count_invalid');
      }
      final headerLength = _decodeU32(await _readExact(input, 4));
      if (headerLength > _maxJsonBytes) {
        throw const LibraryBackupException('backup_header_too_large');
      }
      final header = Map<String, Object?>.from(
        jsonDecode(utf8.decode(await _readExact(input, headerLength))) as Map,
      );

      for (var index = 0; index < count; index++) {
        final pathLength = _decodeU32(await _readExact(input, 4));
        if (pathLength < 1 || pathLength > _maxPathBytes) {
          throw const LibraryBackupException(
            'backup_entry_path_length_invalid',
          );
        }
        final archivePath = utf8.decode(await _readExact(input, pathLength));
        if (!_isSafeArchivePath(archivePath) ||
            extracted.containsKey(archivePath)) {
          throw LibraryBackupException(
            'backup_entry_path_unsafe_or_duplicate',
            arguments: {'path': archivePath},
          );
        }
        final size = _decodeU64(await _readExact(input, 8));
        if (size < 0 || size > _maxEntryBytes) {
          throw const LibraryBackupException('backup_entry_size_invalid');
        }

        File? outputFile;
        RandomAccessFile? output;
        if (extract) {
          outputFile = File(
            path_util.joinAll([staging.path, ...archivePath.split('/')]),
          );
          await outputFile.parent.create(recursive: true);
          output = await outputFile.open(mode: FileMode.write);
        }
        final digestSink = _DigestSink();
        final hashInput = sha256.startChunkedConversion(digestSink);
        var remaining = size;
        while (remaining > 0) {
          final chunkSize = min(remaining, 256 * 1024);
          final chunk = await _readExact(input, chunkSize);
          hashInput.add(chunk);
          if (output != null) await output.writeFrom(chunk);
          remaining -= chunk.length;
        }
        hashInput.close();
        await output?.flush();
        await output?.close();
        final expectedHash = await _readExact(input, 32);
        final actual = digestSink.value;
        if (actual == null ||
            !_constantTimeEquals(actual.bytes, expectedHash)) {
          if (outputFile != null && await outputFile.exists()) {
            await outputFile.delete();
          }
          throw LibraryBackupException(
            'backup_entry_hash_mismatch',
            arguments: {'path': archivePath},
          );
        }
        extracted[archivePath] = _VerifiedEntry(
          size: size,
          sha256: actual.toString(),
        );
      }

      final manifestLength = _decodeU64(await _readExact(input, 8));
      if (manifestLength < 2 || manifestLength > _maxJsonBytes) {
        throw const LibraryBackupException('backup_manifest_size_invalid');
      }
      final manifestBytes = await _readExact(input, manifestLength);
      final expectedManifestHash = await _readExact(input, 32);
      if (!_constantTimeEquals(
        sha256.convert(manifestBytes).bytes,
        expectedManifestHash,
      )) {
        throw const LibraryBackupException('backup_manifest_hash_mismatch');
      }
      _expectBytes(
        await _readExact(input, _trailer.length),
        _trailer,
        'trailer',
      );
      if (await input.position() != await input.length()) {
        throw const LibraryBackupException('backup_trailing_data_invalid');
      }

      final manifest = LibraryBackupManifest.fromJson(
        Map<String, Object?>.from(
          jsonDecode(utf8.decode(manifestBytes)) as Map,
        ),
      );
      if (manifest.formatVersion != version ||
          manifest.backupId != header['backup_id'] ||
          manifest.createdAt.toIso8601String() != header['created_at'] ||
          manifest.entries.length != count) {
        throw const LibraryBackupException('backup_manifest_header_mismatch');
      }
      if (manifest.backupId.isEmpty || manifest.appVersion.isEmpty) {
        throw const LibraryBackupException(
          'backup_manifest_version_info_missing',
        );
      }
      final manifestPaths = <String>{};
      final originalPathOwners = <String, String>{};
      var databaseEntries = 0;
      for (final entry in manifest.entries) {
        if (!manifestPaths.add(entry.archivePath) ||
            !_isSafeArchivePath(entry.archivePath)) {
          throw const LibraryBackupException(
            'backup_manifest_path_unsafe_or_duplicate',
          );
        }
        if (entry.size < 0 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.sha256) ||
            entry.roles.isEmpty) {
          throw LibraryBackupException(
            'backup_manifest_entry_invalid',
            arguments: {'path': entry.archivePath},
          );
        }
        if (entry.archivePath == 'database/sonar_vault.db') {
          databaseEntries++;
          if (!entry.roles.contains('database') ||
              entry.originalPaths.isNotEmpty) {
            throw const LibraryBackupException(
              'backup_manifest_database_role_invalid',
            );
          }
        }
        for (final originalPath in entry.originalPaths) {
          if (originalPath.trim().isEmpty) {
            throw LibraryBackupException(
              'backup_manifest_empty_original_path',
              arguments: {'path': entry.archivePath},
            );
          }
          final previousOwner = originalPathOwners[originalPath];
          if (previousOwner != null && previousOwner != entry.archivePath) {
            throw const LibraryBackupException(
              'backup_manifest_original_path_conflict',
            );
          }
          originalPathOwners[originalPath] = entry.archivePath;
        }
        final verified = extracted[entry.archivePath];
        if (verified == null ||
            verified.size != entry.size ||
            verified.sha256 != entry.sha256) {
          throw LibraryBackupException(
            'backup_manifest_entry_mismatch',
            arguments: {'path': entry.archivePath},
          );
        }
      }
      if (databaseEntries != 1) {
        throw const LibraryBackupException(
          'backup_manifest_database_count_invalid',
        );
      }
      return manifest;
    } on LibraryBackupException {
      rethrow;
    } on FormatException catch (error) {
      throw LibraryBackupException(
        'backup_metadata_json_invalid',
        arguments: {'cause': '$error'},
      );
    } on FileSystemException catch (error) {
      throw LibraryBackupException(
        'backup_read_failed',
        arguments: {'cause': error.message},
      );
    } finally {
      await input?.close();
    }
  }

  String _newId(String prefix) {
    final now = _clock().toUtc().microsecondsSinceEpoch;
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return '$prefix-$now-$random';
  }
}

/// Coalesces database mutations into lightweight automatic snapshots and
/// keeps only a bounded history. A minimum interval avoids repeatedly hashing
/// the database and managed visual assets for every play-count update. Track
/// media and MVs are deliberately excluded; portable restores must use a
/// manual complete backup.
class AutoBackupCoordinator {
  AutoBackupCoordinator({
    required this.service,
    required this.database,
    this.changeDebounce = const Duration(minutes: 2),
    this.minimumInterval = const Duration(hours: 6),
    this.maximumInterval = const Duration(hours: 24),
    this.initialDelay = const Duration(seconds: 30),
    this.retryDelay = const Duration(hours: 1),
    this.keep = 3,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LibraryBackupService service;
  final LibraryDatabase database;
  final Duration changeDebounce;
  final Duration minimumInterval;
  final Duration maximumInterval;
  final Duration initialDelay;
  final Duration retryDelay;
  final int keep;
  final DateTime Function() _clock;
  StreamSubscription<void>? _subscription;
  Timer? _timer;
  Future<void>? _activeRun;
  bool _disposed = false;
  int _changeGeneration = 0;

  Future<void> start() async {
    if (_subscription != null) return;
    _disposed = false;
    _subscription = database.changes.listen((_) => _scheduleAfterChange());
    try {
      final backups = await service.automaticBackups();
      if (backups.isEmpty ||
          _clock().difference(await backups.first.lastModified()) >=
              maximumInterval) {
        // Let the first frame and audio engine settle before hashing a possibly
        // very large library. The work itself stays fully streaming.
        _schedule(initialDelay, _run);
        return;
      }
      final age = _clock().difference(await backups.first.lastModified());
      _schedule(_boundedDelay(maximumInterval - age, maximumInterval), _run);
    } catch (_) {
      // Backup storage being unavailable must never prevent offline startup.
      _schedule(retryDelay, _run);
    }
  }

  void _scheduleAfterChange() {
    _changeGeneration++;
    _schedule(changeDebounce, _runAfterChange);
  }

  Future<void> _runAfterChange() async {
    final generationAtStart = _changeGeneration;
    try {
      final backups = await service.automaticBackups();
      if (generationAtStart != _changeGeneration) {
        _schedule(changeDebounce, _runAfterChange);
        return;
      }
      if (backups.isEmpty) {
        await _run();
        return;
      }
      final age = _clock().difference(await backups.first.lastModified());
      if (age >= minimumInterval) {
        await _run();
      } else {
        _schedule(_boundedDelay(minimumInterval - age, minimumInterval), _run);
      }
    } catch (_) {
      _schedule(retryDelay, _run);
    }
  }

  Future<void> _run() {
    final active = _activeRun;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _performBackup().whenComplete(() {
      if (identical(_activeRun, operation)) _activeRun = null;
    });
    _activeRun = operation;
    return operation;
  }

  Future<void> _performBackup() async {
    final generationAtStart = _changeGeneration;
    var succeeded = false;
    try {
      await service.createAutomaticBackup(keep: keep);
      succeeded = true;
    } catch (_) {
      // Automatic backup must never make local playback or startup fail. A
      // bounded retry still runs even when the library has no later mutation.
    } finally {
      if (generationAtStart != _changeGeneration) {
        _schedule(changeDebounce, _runAfterChange);
      } else {
        _schedule(succeeded ? maximumInterval : retryDelay, _run);
      }
    }
  }

  void _schedule(Duration delay, Future<void> Function() callback) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      unawaited(callback());
    });
  }

  Duration _boundedDelay(Duration delay, Duration upperBound) {
    if (delay.isNegative) return Duration.zero;
    if (delay > upperBound) return upperBound;
    return delay;
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _activeRun;
  }
}

class _BackupSource {
  const _BackupSource({
    required this.file,
    required this.archivePath,
    required this.roles,
    required this.originalPaths,
  });

  final File file;
  final String archivePath;
  final Set<String> roles;
  final List<String> originalPaths;
}

class _VerifiedEntry {
  const _VerifiedEntry({required this.size, required this.sha256});

  final int size;
  final String sha256;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

Future<Digest> _copyAndHash(File source, RandomAccessFile output) async {
  final sink = _DigestSink();
  final hashInput = sha256.startChunkedConversion(sink);
  await for (final chunk in source.openRead()) {
    hashInput.add(chunk);
    await output.writeFrom(chunk);
  }
  hashInput.close();
  final result = sink.value;
  if (result == null) throw StateError('SHA-256 did not produce a digest.');
  return result;
}

Future<void> _copyFileStreaming(File source, File destination) async {
  final output = await destination.open(mode: FileMode.write);
  try {
    await for (final chunk in source.openRead()) {
      await output.writeFrom(chunk);
    }
    await output.flush();
  } finally {
    await output.close();
  }
}

Future<bool> _filesEqualBySha256(File first, File second) async {
  if (await first.length() != await second.length()) return false;
  final firstDigest = await _fileSha256(first);
  final secondDigest = await _fileSha256(second);
  return _constantTimeEquals(firstDigest.bytes, secondDigest.bytes);
}

Future<Digest> _fileSha256(File file) => sha256.bind(file.openRead()).first;

Future<void> _writeJsonAtomically(
  File destination,
  Map<String, Object?> value,
) async {
  final partial = File('${destination.path}.partial');
  if (await partial.exists()) await partial.delete();
  await partial.writeAsString(jsonEncode(value), flush: true);
  if (await destination.exists()) await destination.delete();
  await partial.rename(destination.path);
}

Future<void> _deleteSidecars(String databasePath) async {
  for (final suffix in const ['-wal', '-shm', '-journal']) {
    final sidecar = File('$databasePath$suffix');
    if (await sidecar.exists()) await sidecar.delete();
  }
}

Future<Uint8List> _readExact(RandomAccessFile input, int count) async {
  if (count < 0) {
    throw const LibraryBackupException('backup_length_field_invalid');
  }
  final result = BytesBuilder(copy: false);
  var remaining = count;
  while (remaining > 0) {
    final chunk = await input.read(min(remaining, 256 * 1024));
    if (chunk.isEmpty) {
      throw const LibraryBackupException('backup_file_truncated');
    }
    result.add(chunk);
    remaining -= chunk.length;
  }
  return result.takeBytes();
}

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

Uint8List _u64(int value) =>
    (ByteData(8)..setUint64(0, value, Endian.little)).buffer.asUint8List();

int _decodeU32(Uint8List bytes) =>
    ByteData.sublistView(bytes).getUint32(0, Endian.little);

int _decodeU64(Uint8List bytes) =>
    ByteData.sublistView(bytes).getUint64(0, Endian.little);

void _expectBytes(List<int> actual, List<int> expected, String label) {
  if (!_constantTimeEquals(actual, expected)) {
    throw LibraryBackupException(
      'backup_signature_mismatch',
      arguments: {'part': label},
    );
  }
}

bool _constantTimeEquals(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}

bool _isSafeArchivePath(String value) {
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.startsWith('\\') ||
      value.contains('\\') ||
      value.contains(':')) {
    return false;
  }
  final parts = value.split('/');
  return parts.every((part) => part.isNotEmpty && part != '.' && part != '..');
}

bool _isDescendant(Directory root, String candidate) {
  if (candidate.isEmpty) return false;
  final rootPath = path_util.normalize(root.absolute.path);
  final candidatePath = path_util.normalize(File(candidate).absolute.path);
  return path_util.isWithin(rootPath, candidatePath);
}

String _safeExtension(String filePath) {
  final extension = path_util.extension(filePath).toLowerCase();
  return RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension) ? extension : '';
}

bool _sameFilePath(String first, String second) {
  var normalizedFirst = path_util.normalize(File(first).absolute.path);
  var normalizedSecond = path_util.normalize(File(second).absolute.path);
  if (Platform.isWindows) {
    normalizedFirst = normalizedFirst.toLowerCase();
    normalizedSecond = normalizedSecond.toLowerCase();
  }
  return normalizedFirst == normalizedSecond;
}

String _filePathKey(String value) {
  var normalized = path_util.normalize(File(value).absolute.path);
  if (Platform.isWindows) normalized = normalized.toLowerCase();
  return normalized;
}
