import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/features/library/domain/track.dart';
import 'package:sonar_vault/features/library/domain/track_identification.dart';

void main() {
  group('TrackNameParser', () {
    test(
      'extracts episode title and bracketed artist from noisy file name',
      () {
        final parsed = TrackNameParser.parse(
          fileName: '01 - 【毛不易】毛不易精选歌曲合集（带歌词 分集播放）《消愁》《像我这样的人》《平凡的一天》 p01 01. 像我这样的人 [BV11M411n7TC_p1]-1786841108.mp3',
          isVideo: false,
        );

        expect(parsed.title, '像我这样的人');
        expect(parsed.artist, '毛不易');
        expect(parsed.album, isEmpty);
        expect(parsed.usedFileNameFallback, isTrue);
      },
    );

    test('keeps reliable embedded metadata', () {
      final parsed = TrackNameParser.parse(
        fileName: 'messy-download-name-1786841108.mp3',
        taggedTitle: '平凡的一天',
        taggedArtist: '毛不易',
        taggedAlbum: '平凡的一天',
        isVideo: false,
      );

      expect(parsed.title, '平凡的一天');
      expect(parsed.artist, '毛不易');
      expect(parsed.album, '平凡的一天');
      expect(parsed.usedFileNameFallback, isFalse);
    });

    test('rejects raw Bilibili identifier as a reliable title', () {
      expect(
        TrackNameParser.isReliableTitle(
          '【4K60FPS】演唱会 [BV1abcDEF123]',
          fileName: 'download',
        ),
        isFalse,
      );
    });
  });

  group('needsSmartOrganization', () {
    Track track({
      required String title,
      required String artist,
      String album = '',
      String path = r'E:\Music\song.mp3',
    }) => Track(
      id: 1,
      path: path,
      title: title,
      artist: artist,
      album: album,
      duration: const Duration(minutes: 4),
      fileSize: 1024,
      contentHash: 'hash',
      importedAt: DateTime(2026),
    );

    test('selects raw or unknown metadata for batch organization', () {
      expect(
        needsSmartOrganization(
          track(title: '01 - 演唱会 [BV11M411n7TC]', artist: '未知歌手'),
        ),
        isTrue,
      );
      expect(
        needsSmartOrganization(track(title: 'IMG_5921', artist: '本地视频')),
        isTrue,
      );
    });

    test('does not scan a recognizable single just because album is empty', () {
      expect(
        needsSmartOrganization(track(title: '像我这样的人', artist: '毛不易')),
        isFalse,
      );
    });
  });
}
