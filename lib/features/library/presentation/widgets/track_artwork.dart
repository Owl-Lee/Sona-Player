import 'package:flutter/material.dart';

import '../../../../core/localization/sona_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/track.dart';

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    super.key,
    required this.track,
    this.size = 48,
    this.borderRadius = 13,
  });

  final Track? track;
  final double size;
  final double borderRadius;

  static const _palettes = <List<Color>>[
    [Color(0xFF375A4B), AppColors.mint],
    [Color(0xFF40366B), AppColors.lavender],
    [Color(0xFF693D3A), AppColors.coral],
    [Color(0xFF234D66), Color(0xFF82D8FF)],
    [Color(0xFF664F24), Color(0xFFFFD778)],
  ];

  @override
  Widget build(BuildContext context) {
    final seed =
        track?.contentHash.codeUnits.fold<int>(0, (a, b) => a + b) ?? 0;
    final palette = _palettes[seed % _palettes.length];
    final label = artworkLabelForTitle(
      track == null ? null : context.metadata(track!.title),
    );
    final labelLength = label.characters.length;
    final displayLabel = artworkDisplayLabel(label);
    final fontSize =
        size *
        switch (labelLength) {
          <= 2 => 0.34,
          3 => 0.29,
          4 => 0.285,
          _ => 0.265,
        };
    final baseTextStyle = TextStyle(
      fontSize: fontSize,
      height: 0.96,
      fontWeight: FontWeight.w600,
      letterSpacing: labelLength > 3 ? -0.08 : 0,
    );
    final textLines = labelLength > 3 ? 2 : 1;

    Text artworkText(TextStyle style) {
      return Text(
        displayLabel,
        maxLines: textLines,
        textAlign: TextAlign.center,
        overflow: TextOverflow.clip,
        textScaler: TextScaler.noScaling,
        strutStyle: StrutStyle(
          fontSize: fontSize,
          height: 0.96,
          forceStrutHeight: true,
        ),
        style: style,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.last.withValues(alpha: 0.13),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.9,
        height: size * 0.8,
        child: Center(
          child: artworkText(
            baseTextStyle.copyWith(
              color: Colors.white,
              shadows: const [
                Shadow(
                  color: Color(0x4D000000),
                  blurRadius: 0.8,
                  offset: Offset(0, 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Balances longer artwork labels over two crisp, readable lines.
///
/// The source label is never abbreviated again here: line breaks only change
/// presentation, so a phrase such as “真的爱你” remains semantically complete.
String artworkDisplayLabel(String label) {
  final characters = label.characters.toList(growable: false);
  if (characters.length <= 3) return label;

  if (label.contains(' ')) {
    final words = label.split(RegExp(r'\s+'));
    if (words.length == 2) return '${words.first}\n${words.last}';
  }

  final split = characters.length ~/ 2;
  return '${characters.take(split).join()}\n'
      '${characters.skip(split).join()}';
}

String artworkLabelForTitle(String? title) {
  if (title == null || title.trim().isEmpty) return '♫';
  final cleaned = title
      .replaceAll(RegExp(r'^\s*\d{1,3}\s*[-._、]\s*'), '')
      .replaceAll(RegExp(r'[【\[].*?[】\]]'), ' ')
      .replaceAll(RegExp(r'[《》“”"()]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return '♫';

  // Prefer the first complete phrase. This keeps labels such as “美丽的神话”
  // and “像我这样的人” intact instead of reducing every cover to one glyph.
  var phrase = cleaned
      .split(RegExp(r'\s*[·•|/—–-]\s*'))
      .firstWhere((part) => part.trim().isNotEmpty, orElse: () => cleaned)
      .trim();
  final containsChinese = RegExp(r'[\u3400-\u9FFF]').hasMatch(phrase);
  if (containsChinese && phrase.contains(' ')) {
    phrase = phrase.split(RegExp(r'\s+')).first;
  } else if (!containsChinese && phrase.contains(' ')) {
    final words = phrase.split(RegExp(r'\s+'));
    final complete = <String>[];
    for (final word in words) {
      final candidate = [...complete, word].join(' ');
      if (candidate.characters.length > 6) break;
      complete.add(word);
    }
    phrase = complete.isEmpty ? words.first : complete.join(' ');
  }
  final characters = phrase.characters.toList(growable: false);
  if (characters.length <= 6) return phrase.toUpperCase();

  // At six glyphs, step back to a semantic particle when possible rather
  // than cutting immediately after it.
  const particles = {'的', '之', '与', '和', '與'};
  var end = 6;
  for (var index = 5; index >= 3; index--) {
    if (particles.contains(characters[index])) {
      end = index;
      break;
    }
  }
  if (end < 3) end = 6;
  return characters.take(end).join().toUpperCase();
}
