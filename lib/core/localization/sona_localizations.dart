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
  '切换皮肤': '切換皮膚',
  '播放器背景': '播放器背景',
  '选择一套皮肤，也可以导入并裁切自己的图片。': '選擇一套皮膚，也可以匯入並裁切自己的圖片。',
  '音频声纹识别': '音訊聲紋辨識',
  '全面识别': '全面辨識',
  '全面识别整个曲库': '全面辨識整個曲庫',
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
  '全面识别': 'Identify all',
  '全面识别整个曲库': 'Identify the full library',
  '切换皮肤': 'Change theme',
  '播放器背景': 'Player background',
  '选择一套皮肤，也可以导入并裁切自己的图片。': 'Choose a theme, or import and crop your own image.',
  '曲库里没有可识别的歌曲。': 'There are no tracks to identify.',
  '将逐首扫描曲库中的 {count} 首歌曲。Windows 且已配置 AcoustID 时优先使用音频声纹；其他情况使用标签、文件名和免费公开曲库。所有建议都会先预览，确认后才修改曲库。\n\n公开曲库限制为每秒最多 1 次请求，歌曲较多时会花更长时间。': 'Sona will scan all {count} tracks one by one. On Windows with AcoustID configured, audio fingerprints are tried first; otherwise Sona uses tags, filenames and the free public catalog. Every suggestion is previewed before your library changes.\n\nThe public catalog allows at most one request per second, so larger libraries take longer.',
  '暂不扫描': 'Not now',
  '开始全面识别': 'Identify all',
  '没有发现需要修改的歌曲信息。': 'No metadata changes were found.',
  '已完成 {count} 首歌曲的信息校准。': 'Corrected metadata for {count} tracks.',
  '正在全面识别': 'Identifying full library',
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
  '批量管理': 'Batch manage',
  '全选': 'Select all',
  '取消全选': 'Clear selection',
  '全选全部云端歌曲': 'Select every cloud track',
  '退出批量管理': 'Exit batch mode',
  '删除': 'Delete',
  '正在删除 {completed} / {total} 首': 'Deleting {completed} / {total} tracks',
  '已选 {selected} / {total} 首': 'Selected {selected} / {total} tracks',
  '删除选中的 {count} 首云端歌曲？': 'Delete {count} selected cloud tracks?',
  '删除 {count} 首云副本': 'Delete {count} cloud copies',
  '这些歌曲会从云空间和其他设备可同步内容中移除。\n\n本机文件不会删除；此后它们也不会被自动重新上传。此操作无法撤销。': 'These tracks will be removed from cloud storage and from content available to sync on other devices.\n\nLocal files will not be deleted, and these tracks will not be uploaded again automatically. This cannot be undone.',
  '已从云端删除 {removed} 首歌曲，本机文件保持不变。':
      'Removed {removed} tracks from the cloud. Local files are unchanged.',
  '已删除 {removed} 首，{failed} 首未能删除，请稍后重试。': 'Removed {removed} tracks. {failed} could not be deleted; please try again later.',
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
