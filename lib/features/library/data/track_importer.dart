import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path/path.dart' as path_util;

import '../domain/track.dart';
import '../domain/track_identification.dart';

const supportedAudioExtensions = <String>{
  'mp3',
  'flac',
  'm4a',
  'wav',
  'ogg',
  'opus',
  'aac',
  'aiff',
  'ape',
};

const supportedVideoExtensions = <String>{'mp4', 'mkv', 'mov', 'webm', 'avi'};
const supportedMediaExtensions = <String>{
  ...supportedAudioExtensions,
  ...supportedVideoExtensions,
};

class TrackImporter {
  Future<List<String>> pickAudioFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedMediaExtensions.toList(growable: false),
    );
    return files
        .map((file) => file.path)
        .whereType<String>()
        .toList(growable: false);
  }

  Future<List<String>> pickAudioDirectory() async {
    final directoryPath = await FilePicker.getDirectoryPath(
      dialogTitle: '选择要扫描的音乐 / MV 文件夹',
    );
    if (directoryPath == null) return const [];

    final files = <String>[];
    await for (final entity in Directory(
      directoryPath,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final extension = path_util
          .extension(entity.path)
          .replaceFirst('.', '')
          .toLowerCase();
      if (supportedMediaExtensions.contains(extension)) {
        files.add(entity.path);
      }
    }
    files.sort();
    return files;
  }

  Future<Track> inspect(String filePath) async {
    final track = await Isolate.run(() => _inspectTrack(filePath));
    if (!track.isVideoOnly || track.duration > Duration.zero) return track;
    final duration = await probeVideoDuration(filePath);
    return duration > Duration.zero
        ? track.copyWith(duration: duration)
        : track;
  }

  Future<Duration> probeVideoDuration(String filePath) async {
    final player = Player(
      configuration: const PlayerConfiguration(title: 'Sona 媒体信息'),
    );
    try {
      await player.open(Media(filePath), play: false);
      if (player.state.duration > Duration.zero) return player.state.duration;
      return await player.stream.duration
          .firstWhere((value) => value > Duration.zero)
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      return Duration.zero;
    } finally {
      await player.dispose();
    }
  }
}

Future<Track> _inspectTrack(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('文件不存在', filePath);
  }

  final extension = path_util
      .extension(filePath)
      .replaceFirst('.', '')
      .toLowerCase();
  final isVideo = supportedVideoExtensions.contains(extension);
  AudioMetadata? metadata;
  if (!isVideo) {
    try {
      metadata = readMetadata(file, getImage: false);
    } catch (_) {
      metadata = null;
    }
  }

  final digest = await sha256.bind(file.openRead()).first;
  final stat = await file.stat();
  final parsed = TrackNameParser.parse(
    fileName: path_util.basename(filePath),
    taggedTitle: metadata?.title,
    taggedArtist: metadata?.artist,
    taggedAlbum: metadata?.album,
    isVideo: isVideo,
  );

  return Track(
    path: filePath,
    title: parsed.title,
    artist: parsed.artist,
    album: parsed.album,
    duration: metadata?.duration ?? Duration.zero,
    fileSize: stat.size,
    contentHash: digest.toString(),
    importedAt: DateTime.now(),
    videoPath: isVideo ? filePath : null,
    mediaType: isVideo ? 'video' : 'audio',
  );
}
