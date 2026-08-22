import 'dart:convert';
import 'dart:io';

import '../domain/release_update.dart';

typedef ReleaseJsonFetcher = Future<String> Function(Uri uri);

class ReleaseUpdateService {
  ReleaseUpdateService({this.fetcher, this.repository = 'Owl-Lee/Sona-Player'});

  final ReleaseJsonFetcher? fetcher;
  final String repository;

  Uri get latestReleaseApi =>
      Uri.https('api.github.com', '/repos/$repository/releases/latest');

  Future<ReleaseUpdate?> check({required String currentVersion}) async {
    final payload = await (fetcher ?? _fetch)(latestReleaseApi);
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('GitHub release response is not an object.');
    }
    final release = parseRelease(decoded);
    return isNewerVersion(release.version, currentVersion) ? release : null;
  }

  static ReleaseUpdate parseRelease(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    final page = Uri.tryParse(json['html_url'] as String? ?? '');
    if (tag.isEmpty || page == null || !page.hasScheme) {
      throw const FormatException(
        'GitHub release is missing tag_name/html_url.',
      );
    }
    final assets = <ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map) continue;
        final name = item['name'];
        final url = Uri.tryParse(item['browser_download_url'] as String? ?? '');
        if (name is! String || url == null || !url.hasScheme) continue;
        assets.add(
          ReleaseAsset(
            name: name,
            downloadUrl: url,
            size: (item['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }
    return ReleaseUpdate(
      version: normalizedVersion(tag),
      tagName: tag,
      releasePage: page,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      notes: json['body'] as String? ?? '',
      assets: List.unmodifiable(assets),
      isPrerelease: json['prerelease'] == true,
    );
  }

  static bool isNewerVersion(String candidate, String current) {
    final left = _SemanticVersion.parse(candidate);
    final right = _SemanticVersion.parse(current);
    return left.compareTo(right) > 0;
  }

  static String normalizedVersion(String input) {
    var value = input.trim();
    if (value.toLowerCase().startsWith('v')) value = value.substring(1);
    return value.split('+').first;
  }

  static Future<String> _fetch(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'Sona update checker');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'GitHub returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}

class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion(this.parts, this.preRelease);

  final List<int> parts;
  final List<String> preRelease;

  factory _SemanticVersion.parse(String input) {
    final normalized = ReleaseUpdateService.normalizedVersion(input);
    final dashIndex = normalized.indexOf('-');
    final core = dashIndex < 0
        ? normalized
        : normalized.substring(0, dashIndex);
    final preRelease = dashIndex < 0 ? '' : normalized.substring(dashIndex + 1);
    final numbers = core
        .split('.')
        .map((value) {
          final match = RegExp(r'^\d+').firstMatch(value);
          return int.tryParse(match?.group(0) ?? '') ?? 0;
        })
        .toList(growable: false);
    final padded = List<int>.generate(
      3,
      (index) => index < numbers.length ? numbers[index] : 0,
    );
    final pre = preRelease.isNotEmpty
        ? preRelease.split('.').where((value) => value.isNotEmpty).toList()
        : const <String>[];
    return _SemanticVersion(padded, pre);
  }

  @override
  int compareTo(_SemanticVersion other) {
    for (var index = 0; index < 3; index++) {
      final comparison = parts[index].compareTo(other.parts[index]);
      if (comparison != 0) return comparison;
    }
    if (preRelease.isEmpty && other.preRelease.isNotEmpty) return 1;
    if (preRelease.isNotEmpty && other.preRelease.isEmpty) return -1;
    final length = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var index = 0; index < length; index++) {
      if (index >= preRelease.length) return -1;
      if (index >= other.preRelease.length) return 1;
      final leftNumber = int.tryParse(preRelease[index]);
      final rightNumber = int.tryParse(other.preRelease[index]);
      final comparison = leftNumber != null && rightNumber != null
          ? leftNumber.compareTo(rightNumber)
          : leftNumber != null
          ? -1
          : rightNumber != null
          ? 1
          : preRelease[index].compareTo(other.preRelease[index]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}
