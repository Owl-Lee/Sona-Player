import 'package:pinyin/pinyin.dart' show ChineseHelper;

/// Normalizes Chinese metadata to Simplified Chinese while preserving Latin
/// letters, numbers, punctuation, and all other scripts.
String toSimplifiedChinese(String value) {
  if (value.trim().isEmpty) return value;
  return ChineseHelper.convertToSimplifiedChinese(value);
}
