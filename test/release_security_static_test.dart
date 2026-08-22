import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('release security invariants', () {
    test('release tag is never interpolated directly into PowerShell', () {
      final workflow = _read('.github/workflows/release.yml');
      expect(
        RegExp(r"run:\s*.*\$\{\{\s*github\.ref_name\s*\}\}").hasMatch(workflow),
        isFalse,
      );
      expect(workflow, contains(r'RELEASE_TAG: ${{ github.ref_name }}'));
      expect(workflow, contains(r'-Tag $env:RELEASE_TAG'));
    });

    test('Android system backup and device transfer are disabled', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      final legacyRules = _read(
        'android/app/src/main/res/xml/backup_rules.xml',
      );
      final modernRules = _read(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      );

      expect(manifest, contains('android:allowBackup="false"'));
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      expect(legacyRules, contains('<exclude domain="database" path="."'));
      expect(modernRules, contains('<device-transfer>'));
      expect(modernRules, contains('<exclude domain="sharedpref" path="."'));
    });

    test('Android playback notification permission is user initiated', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      final activity = _read(
        'android/app/src/main/kotlin/com/sonarvault/sonar_vault/MainActivity.kt',
      );
      final player = _read(
        'lib/features/player/application/player_controller.dart',
      );

      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(activity, contains('notification_permission_requested'));
      expect(activity, contains('requestForPlayback'));
      expect(
        player,
        contains('requestPlaybackNotificationPermissionIfNeeded()'),
      );
    });

    test('cloud hard delete is routed through the guarded RPC', () {
      final controller = _read(
        'lib/features/cloud/application/cloud_sync_controller.dart',
      );
      final migration = _read(
        'supabase/migrations/202608220002_cloud_delete_policy_hardening.sql',
      );

      expect(
        RegExp(
          r"client\.rpc\(\s*'permanently_delete_cloud_track'",
          multiLine: true,
        ).hasMatch(controller),
        isTrue,
      );
      expect(
        RegExp(
          r"from\('cloud_tracks'\)\s*\.delete\(\)",
          multiLine: true,
        ).hasMatch(controller),
        isFalse,
      );
      expect(migration, contains('There is deliberately no DELETE policy'));
      expect(migration, contains('track.deleted_at is not null'));
      expect(migration, contains('space.owner_id = auth.uid()'));
      expect(migration, contains('space owners delete orphaned media'));
      expect(
        migration,
        isNot(
          contains(
            "public.is_space_member(((storage.foldername(name))[1])::uuid)",
          ),
        ),
        reason: 'malformed Storage object names must deny instead of casting',
      );
      expect(
        RegExp(r"when coalesce\(\(storage\.foldername\(name\)\)\[1\], ''\) ~\*")
            .allMatches(migration),
        hasLength(4),
      );
      expect(
        RegExp(
          r'create policy\s+"[^"]+"\s+on\s+storage\.objects\s+for\s+delete',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(migration),
        hasLength(1),
        reason: 'sona-media must have only the owner/orphan DELETE policy',
      );
      expect(
        migration,
        contains(
          'drop policy if exists "space members access media" on storage.objects;',
        ),
      );
      expect(
        migration,
        contains(
          'drop policy if exists "members manage playlist tracks"\n  on public.cloud_playlist_tracks;',
        ),
      );
      expect(
        migration,
        contains(
          'create policy "members read playlist tracks"\n  on public.cloud_playlist_tracks\n  for select to authenticated',
        ),
      );

      final createdPolicies = RegExp(
        r'create policy\s+"([^"]+)"',
        caseSensitive: false,
      ).allMatches(migration).map((match) => match.group(1)!).toList();
      for (final policy in createdPolicies) {
        expect(
          migration.toLowerCase(),
          contains('drop policy if exists "${policy.toLowerCase()}"'),
          reason: 'migration must be safely rerunnable for policy $policy',
        );
      }
    });

    test('cloud playlist replacement is atomic and owner scoped', () {
      final controller = _read(
        'lib/features/cloud/application/cloud_sync_controller.dart',
      );
      final migration = _read(
        'supabase/migrations/202608220002_cloud_delete_policy_hardening.sql',
      );

      expect(
        RegExp(
          r"client\.rpc\(\s*'replace_cloud_playlist_tracks'",
          multiLine: true,
        ).hasMatch(controller),
        isTrue,
      );
      expect(
        RegExp(
          r"from\('cloud_playlist_tracks'\)\s*\.delete\(\)",
          multiLine: true,
        ).hasMatch(controller),
        isFalse,
      );
      expect(
        controller,
        contains("throw StateError('cloud_playlist_track_not_uploaded')"),
      );
      expect(migration, contains('playlist.owner_id = auth.uid()'));
      expect(migration, contains('playlist.space_id = target_space'));
      expect(migration, contains('track.space_id = playlist_space'));
      expect(migration, contains('track.deleted_at is null'));
      expect(migration, contains('for update;'));
      expect(
        migration,
        contains(
          'revoke all on function public.replace_cloud_playlist_tracks(uuid, uuid, uuid[])',
        ),
      );
      expect(
        RegExp(
          r'grant execute on function public\.replace_cloud_playlist_tracks\(uuid, uuid, uuid\[\]\)\s+to authenticated;',
          caseSensitive: false,
        ).hasMatch(migration),
        isTrue,
      );
    });

    test('portable backups and SQLite sidecars stay out of git', () {
      final ignore = _read('.gitignore');
      expect(ignore, contains('*.sonabackup'));
      expect(ignore, contains('*.db-wal'));
      expect(ignore, contains('*.db-shm'));
      expect(ignore, contains('*.db-journal'));
    });

    test('restore snapshots WAL before removing SQLite sidecars', () {
      final service = _read(
        'lib/features/library/data/library_backup_service.dart',
      );
      final snapshot = service.indexOf(
        'await _createConsistentRollbackSnapshot(target, rollbackPartial);',
      );
      final sidecarRemoval = service.indexOf(
        'await _deleteSidecars(target.path);',
        snapshot,
      );

      expect(snapshot, greaterThanOrEqualTo(0));
      expect(sidecarRemoval, greaterThan(snapshot));
      expect(service, isNot(contains('await target.rename(rollback.path);')));
    });

    test('full-backup UI warns that exported user data is unencrypted', () {
      final settings = _read(
        'lib/features/settings/presentation/settings_page.dart',
      );
      final backupService = _read(
        'lib/features/library/data/library_backup_service.dart',
      );

      expect(settings, contains('它可能包含歌曲、MV、封面和本地设置，且当前未加密'));
      expect(settings, contains('数据库、歌曲、MV、封面、自定义壁纸和本地设置'));
      expect(backupService, contains("archivePath: 'database/sonar_vault.db'"));
      expect(backupService, contains('originalPaths: [reference.path]'));
    });
  });
}
