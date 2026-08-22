import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/features/settings/application/release_update_service.dart';

void main() {
  test(
    'detects a newer release and preserves stable download assets',
    () async {
      final service = ReleaseUpdateService(
        fetcher: (_) async => jsonEncode({
          'tag_name': 'v0.5.0',
          'html_url':
              'https://github.com/Owl-Lee/Sona-Player/releases/tag/v0.5.0',
          'published_at': '2026-08-22T10:00:00Z',
          'body': 'Stability release',
          'prerelease': false,
          'assets': [
            {
              'name': 'checksums.sha256',
              'browser_download_url': 'https://example.com/checksums.sha256',
              'size': 1,
            },
            {
              'name': 'Sona-Windows-x64.zip',
              'browser_download_url':
                  'https://example.com/Sona-Windows-x64.zip',
              'size': 42,
            },
            {
              'name': 'Sona-Windows-x64-Setup.exe',
              'browser_download_url':
                  'https://example.com/Sona-Windows-x64-Setup.exe',
              'size': 64,
            },
            {
              'name': 'debug-universal.apk',
              'browser_download_url': 'https://example.com/debug-universal.apk',
              'size': 21,
            },
            {
              'name': 'Sona-Android.apk',
              'browser_download_url': 'https://example.com/Sona-Android.apk',
              'size': 84,
            },
          ],
        }),
      );

      final update = await service.check(currentVersion: '0.4.51+2070');
      expect(update?.version, '0.5.0');
      expect(update?.assetForPlatform(windows: true, android: false)?.size, 64);
      expect(update?.assetForPlatform(windows: false, android: true)?.size, 84);
    },
  );

  test('platform asset selection falls back only after exact public names', () {
    final update = ReleaseUpdateService.parseRelease({
      'tag_name': 'v0.5.0',
      'html_url': 'https://example.com/releases/v0.5.0',
      'assets': [
        {
          'name': 'Sona-Windows-x64.zip',
          'browser_download_url': 'https://example.com/windows.zip',
        },
        {
          'name': 'fallback.apk',
          'browser_download_url': 'https://example.com/fallback.apk',
        },
      ],
    });

    expect(
      update.assetForPlatform(windows: true, android: false)?.name,
      'Sona-Windows-x64.zip',
    );
    expect(
      update.assetForPlatform(windows: false, android: true)?.name,
      'fallback.apk',
    );
  });

  test('stable is newer than prerelease but an older release is ignored', () {
    expect(ReleaseUpdateService.isNewerVersion('0.5.0', '0.5.0-rc.2'), isTrue);
    expect(ReleaseUpdateService.isNewerVersion('v0.4.51', '0.5.0'), isFalse);
    expect(
      ReleaseUpdateService.isNewerVersion('0.5.0-rc.2', '0.5.0-rc.10'),
      isFalse,
    );
  });

  test('rejects malformed release metadata', () {
    expect(
      () => ReleaseUpdateService.parseRelease({'tag_name': 'v0.5.0'}),
      throwsFormatException,
    );
  });
}
