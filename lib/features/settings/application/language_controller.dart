import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/data/library_database.dart';

enum AppLanguage {
  simplifiedChinese(
    'zh-Hans',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ),
  traditionalChinese(
    'zh-Hant',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ),
  english('en', Locale('en'));

  const AppLanguage(this.storageValue, this.locale);

  final String storageValue;
  final Locale locale;

  static AppLanguage fromStorage(String? value) => values.firstWhere(
    (item) => item.storageValue == value,
    orElse: () => simplifiedChinese,
  );
}

class LanguageState {
  const LanguageState({
    this.language = AppLanguage.simplifiedChinese,
    this.isLoading = true,
  });

  final AppLanguage language;
  final bool isLoading;
}

final languageControllerProvider =
    StateNotifierProvider<LanguageController, LanguageState>((ref) {
      final controller = LanguageController(ref.watch(libraryDatabaseProvider));
      Future<void>.microtask(controller.load);
      return controller;
    });

class LanguageController extends StateNotifier<LanguageState> {
  LanguageController(this._database) : super(const LanguageState());

  final LibraryDatabase _database;

  Future<void> load() async {
    final stored = await _database.getSetting('interface.language');
    state = LanguageState(
      language: AppLanguage.fromStorage(stored),
      isLoading: false,
    );
  }

  Future<void> select(AppLanguage language) async {
    if (state.language == language && !state.isLoading) return;
    state = LanguageState(language: language, isLoading: false);
    await _database.setSetting('interface.language', language.storageValue);
  }
}
