import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/localization/sona_localizations.dart';
import 'package:sonar_vault/features/settings/application/language_controller.dart';

void main() {
  test('resolves all persisted language values', () {
    expect(AppLanguage.fromStorage('zh-Hans'), AppLanguage.simplifiedChinese);
    expect(AppLanguage.fromStorage('zh-Hant'), AppLanguage.traditionalChinese);
    expect(AppLanguage.fromStorage('en'), AppLanguage.english);
    expect(AppLanguage.fromStorage('damaged'), AppLanguage.simplifiedChinese);
  });

  test('localizes core navigation and settings copy', () {
    expect(
      const SonaLocalizations(Locale('en')).text('外观与播放器'),
      'Appearance & player',
    );
    expect(
      const SonaLocalizations(
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ).text('设置'),
      '設定',
    );
    expect(const SonaLocalizations(Locale('zh')).text('设置'), '设置');
  });

  test('localizes metadata for display without changing the stored source', () {
    const traditional = SonaLocalizations(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    const english = SonaLocalizations(Locale('en'));
    expect(traditional.metadata('美丽的神话'), '美麗的神話');
    expect(english.metadata('成龙'), 'Cheng Long');
    expect(english.metadata('Eason Chan'), 'Eason Chan');
  });
}
