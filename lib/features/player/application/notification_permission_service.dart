import 'dart:io';

import 'package:flutter/services.dart';

const _notificationPermissionChannel = MethodChannel(
  'com.sonarvault.sona/notification_permission',
);

/// Requests Android 13+'s notification permission only after an explicit
/// playback action. Native code remembers that the prompt was already shown,
/// so a denial never turns rapid play taps or later launches into prompt spam.
/// Playback itself intentionally continues regardless of the result.
Future<bool> requestPlaybackNotificationPermissionIfNeeded() async {
  if (!Platform.isAndroid) return true;
  try {
    return await _notificationPermissionChannel.invokeMethod<bool>(
          'requestForPlayback',
        ) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
