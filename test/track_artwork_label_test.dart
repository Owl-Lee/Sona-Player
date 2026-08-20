import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/features/library/presentation/widgets/track_artwork.dart';

void main() {
  test('keeps short semantic song titles intact', () {
    expect(artworkLabelForTitle('美丽的神话 I'), '美丽的神话');
    expect(artworkLabelForTitle('真的爱你'), '真的爱你');
    expect(artworkLabelForTitle('像我这样的人'), '像我这样的人');
    expect(artworkLabelForTitle('Mei Li De Shen Hua'), 'MEI LI');
  });

  test('removes download noise before building the artwork label', () {
    expect(artworkLabelForTitle('01 - 【4K60FPS】《消愁》'), '消愁');
  });

  test('balances longer artwork labels without dropping title characters', () {
    expect(artworkDisplayLabel('真的爱你'), '真的\n爱你');
    expect(artworkDisplayLabel('可惜没如果'), '可惜\n没如果');
    expect(artworkDisplayLabel('美丽的神话'), '美丽\n的神话');
    expect(artworkDisplayLabel('MEI LI'), 'MEI\nLI');
  });
}
