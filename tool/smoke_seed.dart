import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3 ||
      (arguments.first != 'seed' && arguments.first != 'clean')) {
    stderr.writeln(
      'Usage: dart run tool/smoke_seed.dart <seed|clean> <database> <audio>',
    );
    exitCode = 64;
    return;
  }

  final operation = arguments[0];
  final databasePath = arguments[1];
  final audioPath = arguments[2];
  final audioFile = File(audioPath);
  final digest = await sha256.bind(audioFile.openRead()).first;

  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(databasePath);
  try {
    if (operation == 'clean') {
      await database.delete(
        'tracks',
        where: 'content_hash = ?',
        whereArgs: [digest.toString()],
      );
      stdout.writeln('Smoke-test track removed.');
      return;
    }

    final fileStat = await audioFile.stat();
    await database.insert('tracks', {
      'path': audioFile.absolute.path,
      'title': 'SonarVault 播放测试',
      'artist': '声仓实验室',
      'album': 'MVP Smoke Test',
      'duration_ms': 8000,
      'file_size': fileStat.size,
      'content_hash': digest.toString(),
      'imported_at': DateTime.now().toIso8601String(),
      'is_favorite': 0,
      'play_count': 0,
      'last_played_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    stdout.writeln('Smoke-test track inserted.');
  } finally {
    await database.close();
  }
}
