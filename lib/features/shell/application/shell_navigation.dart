import 'package:flutter_riverpod/flutter_riverpod.dart';

final shellDestinationProvider = StateProvider<int>((ref) => 0);

bool canExitMobileShell({
  required int destination,
  required bool selectionActive,
}) => destination == 0 && !selectionActive;
