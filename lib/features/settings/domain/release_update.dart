class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final Uri downloadUrl;
  final int size;
}

class ReleaseUpdate {
  const ReleaseUpdate({
    required this.version,
    required this.tagName,
    required this.releasePage,
    required this.publishedAt,
    required this.notes,
    required this.assets,
    required this.isPrerelease,
  });

  final String version;
  final String tagName;
  final Uri releasePage;
  final DateTime? publishedAt;
  final String notes;
  final List<ReleaseAsset> assets;
  final bool isPrerelease;

  ReleaseAsset? assetForPlatform({
    required bool windows,
    required bool android,
  }) {
    ReleaseAsset? exact(String name) {
      final normalized = name.toLowerCase();
      for (final asset in assets) {
        if (asset.name.toLowerCase() == normalized) return asset;
      }
      return null;
    }

    if (windows) {
      final installer = exact('Sona-Windows-x64-Setup.exe');
      if (installer != null) return installer;
      for (final asset in assets) {
        if (asset.name.toLowerCase().endsWith('.zip')) return asset;
      }
      return null;
    }
    if (android) {
      final apk = exact('Sona-Android.apk');
      if (apk != null) return apk;
      for (final asset in assets) {
        if (asset.name.toLowerCase().endsWith('.apk')) return asset;
      }
    }
    return null;
  }
}
