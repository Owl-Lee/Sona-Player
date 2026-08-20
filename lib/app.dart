import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/settings/application/language_controller.dart';
import 'features/shell/presentation/main_shell.dart';

class SonarVaultApp extends ConsumerWidget {
  const SonarVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageControllerProvider).language;
    return MaterialApp(
      title: 'Sona',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: language.locale,
      supportedLocales: AppLanguage.values.map((item) => item.locale),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainShell(),
    );
  }
}
