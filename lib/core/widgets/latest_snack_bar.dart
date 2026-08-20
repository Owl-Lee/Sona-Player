import 'package:flutter/material.dart';

/// Shows only the latest transient message.
///
/// Rapid actions should reflect the user's current operation instead of
/// forcing older snack bars to finish their display time first.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showLatestSnackBar(
  BuildContext context,
  SnackBar snackBar,
) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..removeCurrentSnackBar()
    ..clearSnackBars();
  return messenger.showSnackBar(snackBar);
}
