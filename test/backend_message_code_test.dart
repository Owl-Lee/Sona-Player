import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/features/cloud/application/cloud_sync_controller.dart';
import 'package:sonar_vault/features/library/domain/library_backup.dart';
import 'package:sonar_vault/features/library/domain/track_identification.dart';
import 'package:sonar_vault/features/player/application/player_controller.dart';

void main() {
  test('controller message codes keep interpolation values separate', () {
    final cloud = const CloudSyncState().copyWith(
      status: 'cloud_syncing_track',
      statusArgs: const {'title': '歌曲'},
    );
    final playback = const PlaybackState().copyWith(
      errorMessage: 'player_error_local_file_missing',
      errorMessageArgs: const {'title': '歌曲'},
    );

    expect(cloud.status, 'cloud_syncing_track');
    expect(cloud.statusArgs, const {'title': '歌曲'});
    expect(playback.errorMessage, 'player_error_local_file_missing');
    expect(playback.errorMessageArgs, const {'title': '歌曲'});

    expect(cloud.copyWith(status: 'cloud_sync_complete').statusArgs, isEmpty);
    expect(playback.copyWith(errorMessage: '').errorMessageArgs, isEmpty);
  });

  test('cloud mutations require the requested row in the response', () {
    expect(cloudMutationAffectedTrack(const [], 'track-1'), isFalse);
    expect(
      cloudMutationAffectedTrack(const [
        {'id': 'track-2'},
      ], 'track-1'),
      isFalse,
    );
    expect(
      cloudMutationAffectedTrack(const [
        {'id': 'track-1'},
      ], 'track-1'),
      isTrue,
    );
  });

  test('backup failures and metadata sentinels are locale independent', () {
    const error = LibraryBackupException(
      'backup_required_media_missing',
      arguments: {'count': '2'},
    );

    expect(error.code, 'backup_required_media_missing');
    expect(error.arguments, const {'count': '2'});
    expect(TrackNameParser.unknownArtist, 'Unknown artist');
    expect(TrackNameParser.localVideoArtist, 'Local video');
    expect(TrackNameParser.standaloneVideoAlbum, 'Standalone MV');
  });
}
