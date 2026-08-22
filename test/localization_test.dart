import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/localization/sona_localizations.dart';
import 'package:sonar_vault/features/player/application/player_controller.dart';
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
    expect(
      const SonaLocalizations(Locale('en')).text('当前没有歌曲'),
      'No song is selected',
    );
    expect(
      const SonaLocalizations(Locale('en')).text('配置免费音频声纹'),
      'Configure free audio fingerprinting',
    );
    expect(
      const SonaLocalizations(Locale('en')).text('流光极彩'),
      'Prismatic Flow',
    );
    expect(const SonaLocalizations(Locale('en')).text('最近'), 'Latest');
    expect(
      const SonaLocalizations(Locale('en')).text('保留静态主题，停用环境动画和实时液态毛玻璃模糊'),
      contains('disable ambient motion and real-time liquid-glass blur'),
    );
    expect(
      const SonaLocalizations(
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ).text('上次恢复未能安全应用'),
      '上次還原未能安全套用',
    );
    expect(
      const SonaLocalizations(Locale('en'))
          .text('轻量自动快照已开启；保存数据库和封面，不重复复制歌曲与 MV，默认保留最新 3 份。'),
      contains('without duplicating songs or MVs'),
    );
  });

  test('localizes metadata for display without changing the stored source', () {
    const simplified = SonaLocalizations(Locale('zh'));
    const traditional = SonaLocalizations(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    const english = SonaLocalizations(Locale('en'));
    const providerTitle = '美麗的神話 I';
    expect(simplified.metadata(providerTitle), '美丽的神话 I');
    expect(traditional.metadata(providerTitle), providerTitle);
    expect(
      english.metadata(providerTitle),
      isNot(contains(RegExp(r'[\u3400-\u9FFF]'))),
    );
    expect(traditional.metadata('美丽的神话'), '美麗的神話');
    expect(english.metadata('成龙'), 'Cheng Long');
    expect(english.metadata('Eason Chan'), 'Eason Chan');
    expect(english.metadata('未知歌手'), 'Unknown artist');
    expect(traditional.metadata('未知专辑'), '未標註專輯');
  });

  test('identification result copy is available in all three languages', () {
    const simplified = SonaLocalizations(Locale('zh'));
    const traditional = SonaLocalizations(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    const english = SonaLocalizations(Locale('en'));

    expect(
      simplified.text('identification_fingerprint_match'),
      '已通过音频声纹找到匹配结果。',
    );
    expect(
      traditional.text('identification_fingerprint_match'),
      '已透過音訊聲紋找到相符結果。',
    );
    expect(
      english.text('identification_fingerprint_match'),
      'A match was found from the audio fingerprint.',
    );
    expect(english.text('manual_edit'), 'Manual edit');
  });

  test('player controls and transient surfaces are localized', () {
    const traditional = SonaLocalizations(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    const english = SonaLocalizations(Locale('en'));

    expect(english.text('播放器设置'), 'Player settings');
    expect(english.text('关闭播放队列'), 'Close play queue');
    expect(
      english.text('MV 画面暂时不可用，音频仍在播放'),
      contains('audio is still playing'),
    );
    expect(
      english.text('来自：{source} · {count} 首'),
      'From: {source} · {count} tracks',
    );
    expect(traditional.text('关联 MV'), '關聯 MV');
    expect(traditional.text('开始定时'), '開始定時');
  });

  test('library, playlist, appearance and playback actions are localized', () {
    const traditional = SonaLocalizations(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    const english = SonaLocalizations(Locale('en'));

    const highRiskKeys = <String>[
      '导入歌曲 / MV',
      '从曲库移除所选歌曲？',
      '添加到哪个歌单？',
      '创建你的第一个歌单',
      '裁切播放器背景',
      '导入自己的背景',
      '列表循环',
      '单曲循环',
      '随机播放',
      '鎏金麦境',
    ];
    for (final key in highRiskKeys) {
      expect(
        english.text(key),
        isNot(contains(RegExp(r'[\u3400-\u9FFF]'))),
        reason: 'English copy is missing for $key',
      );
    }
    expect(traditional.text('导入歌曲 / MV'), '匯入歌曲 / MV');
    expect(traditional.text('单曲循环'), '單曲循環');
    expect(traditional.text('鎏金麦境'), '鎏金麥境');
  });

  test(
    'backend status and player error codes are translated in all locales',
    () {
      const simplified = SonaLocalizations(Locale('zh'));
      const traditional = SonaLocalizations(
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      const english = SonaLocalizations(Locale('en'));

      expect(simplified.text('cloud_sync_planning'), '正在整理同步计划…');
      expect(traditional.text('cloud_sync_planning'), '正在整理同步計畫…');
      expect(english.text('cloud_sync_planning'), 'Preparing the sync plan…');
      expect(english.text('queue_source_local_library'), 'Local library');
      expect(
        english.text('player_error_local_file_missing'),
        contains('{title}'),
      );
    },
  );

  testWidgets(
    'active queue source relocalizes without replacing playback state',
    (tester) async {
      const playback = PlaybackState(
        queueSource: 'queue_source_playlist',
        queueSourceArgs: {'playlist': 'Road Trip'},
      );

      Future<void> pump(Locale locale) => tester.pumpWidget(
        Localizations(
          locale: locale,
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => Text(
                context.trArgs(playback.queueSource, playback.queueSourceArgs),
              ),
            ),
          ),
        ),
      );

      await pump(const Locale('en'));
      expect(find.text('Playlist “Road Trip”'), findsOneWidget);
      await pump(const Locale('zh'));
      expect(find.text('歌单《Road Trip》'), findsOneWidget);
      await pump(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      expect(find.text('播放清單「Road Trip」'), findsOneWidget);
      expect(playback.queueSource, 'queue_source_playlist');
      expect(playback.queueSourceArgs, const {'playlist': 'Road Trip'});
    },
  );

  testWidgets('account and cloud copy follows the active widget locale', (
    tester,
  ) async {
    Future<void> pump(Locale locale) => tester.pumpWidget(
      Localizations(
        locale: locale,
        delegates: const [DefaultWidgetsLocalizations.delegate],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) => Text(
              '${context.tr('云端资料库')}|${context.tr('account_sign_in_success')}',
            ),
          ),
        ),
      ),
    );

    await pump(const Locale('zh'));
    expect(find.text('云端资料库|登录成功，正在检查云端数据。'), findsOneWidget);
    await pump(
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    expect(find.text('雲端資料庫|登入成功，正在檢查雲端資料。'), findsOneWidget);
    await pump(const Locale('en'));
    expect(
      find.text('Cloud library|Signed in. Checking cloud data…'),
      findsOneWidget,
    );
  });

  testWidgets('localized status arguments are interpolated immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: const [DefaultWidgetsLocalizations.delegate],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) => Text(
              context.trArgs('cloud_syncing_track', const {'title': 'Halo'}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Syncing “Halo”…'), findsOneWidget);
    expect(find.textContaining('{title}'), findsNothing);
  });
}
