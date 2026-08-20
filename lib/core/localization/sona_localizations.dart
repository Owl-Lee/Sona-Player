import 'package:flutter/widgets.dart';
import 'package:pinyin/pinyin.dart'
    show ChineseHelper, PinyinFormat, PinyinHelper;

/// Sona keeps Simplified Chinese as the source language. Traditional Chinese
/// is derived with the bundled offline dictionary, while English uses reviewed
/// product copy. Missing English entries deliberately fall back to the source
/// text so a new control never becomes blank.
class SonaLocalizations {
  const SonaLocalizations(this.locale);

  final Locale locale;

  static SonaLocalizations of(BuildContext context) =>
      SonaLocalizations(Localizations.localeOf(context));

  String text(String source) {
    if (locale.languageCode == 'en') return _english[source] ?? source;
    if (locale.scriptCode == 'Hant') {
      return _traditional[source] ??
          ChineseHelper.convertToTraditionalChinese(source);
    }
    return source;
  }

  /// Localizes user-facing music metadata without changing the stored value.
  /// Chinese variants are losslessly converted. English keeps official Latin
  /// metadata as-is and uses title-cased Pinyin only when no Latin name exists.
  String metadata(String source) {
    if (source.trim().isEmpty) return source;
    if (locale.scriptCode == 'Hant') {
      return ChineseHelper.convertToTraditionalChinese(source);
    }
    if (locale.languageCode != 'en' ||
        !RegExp(r'[\u3400-\u9FFF]').hasMatch(source)) {
      return source;
    }
    final pinyin = PinyinHelper.getPinyinE(
      source,
      separator: ' ',
      defPinyin: '',
      format: PinyinFormat.WITHOUT_TONE,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    return pinyin
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word.substring(0, 1).toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}

extension SonaLocalizationContext on BuildContext {
  String tr(String source) => SonaLocalizations.of(this).text(source);
  String metadata(String source) => SonaLocalizations.of(this).metadata(source);
}

const _traditional = <String, String>{
  '设置': '設定',
  '外观与播放器': '外觀與播放器',
  '账号与云同步': '帳號與雲端同步',
  '登录、头像与跨设备同步': '登入、頭像與跨裝置同步',
  '语言': '語言',
  '语言与显示文字': '語言與顯示文字',
  '存储与数据': '儲存與資料',
  '此设备': '此裝置',
  '此设备数据库': '此裝置資料庫',
  '关于': '關於',
  '返回设置': '返回設定',
  '首页': '首頁',
  '曲库': '曲庫',
  '本地曲库': '本機曲庫',
  '歌单': '歌單',
  '我的歌单': '我的歌單',
  '我的收藏': '我的收藏',
  '最近播放': '最近播放',
  'MV 专区': 'MV 專區',
  '听歌排行': '聆聽排行',
  '我的音乐': '我的音樂',
  '常用歌单': '常用歌單',
  '选择常用歌单': '選擇常用歌單',
  '折叠': '收合',
  '展开': '展開',
  '音频声纹识别': '音訊聲紋辨識',
  '正在读取数据库位置…': '正在讀取資料庫位置…',
};

const _english = <String, String>{
  '设置': 'Settings',
  '外观与播放器': 'Appearance & player',
  '账号与云同步': 'Account & cloud sync',
  '登录、头像与跨设备同步': 'Sign in, profile and device sync',
  '语言': 'Languages',
  '语言与显示文字': 'Language and display text',
  '简体中文': 'Simplified Chinese',
  '繁體中文': 'Traditional Chinese',
  '英文': 'English',
  '选择界面语言': 'Choose interface language',
  '切换后立即应用，并在下次启动时保留。':
      'Changes apply immediately and are kept for the next launch.',
  '当前语言': 'Current language',
  '存储与数据': 'Storage & data',
  '此设备': 'this device',
  '关于': 'About',
  '返回设置': 'Back to Settings',
  '此设备数据库': 'On-device database',
  '正在读取数据库位置…': 'Reading database location…',
  '音频声纹识别': 'Audio fingerprint recognition',
  '未配置时仍可使用标签、文件名和 MusicBrainz 后备校准':
      'Tags, filenames and MusicBrainz remain available without a key',
  'AcoustID 已配置 · 声纹不命中时自动回退公开曲库':
      'AcoustID configured · falls back to the public catalog when needed',
  '配置免费 Key': 'Configure free key',
  '已启用': 'Enabled',
  '版本 0.4.26 · Android / Windows': 'Version 0.4.26 · Android / Windows',
  '首页': 'Home',
  '曲库': 'Library',
  '本地曲库': 'Local library',
  '歌单': 'Playlists',
  '我的歌单': 'My playlists',
  '我的收藏': 'Favorites',
  '最近播放': 'Recently played',
  'MV 专区': 'Music videos',
  '听歌排行': 'Listening stats',
  '我的音乐': 'My music',
  '常用歌单': 'Pinned playlists',
  '选择常用歌单': 'Choose pinned playlists',
  '取消': 'Cancel',
  '保存': 'Save',
  '折叠': 'Collapse',
  '展开': 'Expand',
  '首': ' tracks',
  '我的背景': 'My background',
  '只属于你的音乐空间': 'Your personal music space',
  '导入音乐': 'Import music',
  '本地歌曲': 'Local tracks',
  '已配对 MV': 'Paired videos',
  '个': 'items',
  'AI 识别歌曲信息': 'Identify song information',
  '取消收藏': 'Remove from favorites',
  '收藏': 'Favorite',
  '加入歌单': 'Add to playlist',
  '从最近播放中移除': 'Remove from recently played',
  '从听歌排行中移除': 'Remove from listening stats',
  '从歌单中移除': 'Remove from playlist',
  '从本地曲库移除': 'Remove from local library',
  '从本地曲库移除？': 'Remove from local library?',
  '移除': 'Remove',
  '正在分析标签、文件名和公开曲库…': 'Analyzing tags, filename and public catalogs…',
  '识别结果': 'Identification result',
  '歌曲': 'Song',
  '歌手': 'Artist',
  '专辑': 'Album',
  '未提供': 'Not provided',
  '保留原信息': 'Keep original',
  '应用校准': 'Apply correction',
  '未标注专辑': 'Album not specified',
  '从云端删除': 'Delete from cloud',
  '最近同步': 'Recently synced',
  '曲名 A–Z': 'Title A–Z',
  '歌手 A–Z': 'Artist A–Z',
  '专辑 A–Z': 'Album A–Z',
  '文件大小': 'File size',
  '可信度': 'Confidence',
  '将不再显示在 Sona 中，电脑里的原始文件不会被删除。': ' will no longer appear in Sona. The original file on this computer will not be deleted.',
  'AcoustID 音频声纹': 'AcoustID audio fingerprint',
  'MusicBrainz 公开曲库': 'MusicBrainz public catalog',
  '本地智能清洗': 'Local metadata cleanup',
  '根据音频内容匹配，与文件名无关。':
      'Matched from audio content independently of the filename.',
  '根据清洗后的曲名、歌手和时长进行联网校准，并非声纹命中。':
      'Matched online using the cleaned title, artist and duration.',
  '还没有播放歌曲': 'Nothing playing yet',
  '从曲库选择一首歌': 'Choose a song from your library',
  '从曲库中选择一首歌，播放控制会出现在这里。':
      'Choose a song from your library to show playback controls here.',
  '去曲库': 'Open library',
  '上一首': 'Previous',
  '下一首': 'Next',
  '播放队列': 'Play queue',
};
