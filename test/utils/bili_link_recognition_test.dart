import 'package:PiliPlus/utils/bili_link_recognition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const video = 'https://www.bilibili.com/video/BV1xx411c7mD';

  test(
    'extracts links from share captions and removes surrounding punctuation',
    () {
      final links = BiliLinkRecognition.parse('分享一个视频：\n《标题》 $video?t=12）。');
      expect(links, [Uri.parse('$video?t=12')]);
    },
  );

  test('deduplicates links in order and upgrades public HTTP links', () {
    expect(
      BiliLinkRecognition.parse('$video\n$video http://b23.tv/abc123'),
      [Uri.parse(video), Uri.parse('https://b23.tv/abc123')],
    );
  });

  test('accepts bare public domains and supported content schemes', () {
    expect(BiliLinkRecognition.parse('看这里 b23.tv/abc123'), [
      Uri.parse('https://b23.tv/abc123'),
    ]);
    expect(BiliLinkRecognition.parse('www.bilibili.com/video/BV1xx411c7mD'), [
      Uri.parse(video),
    ]);
    expect(BiliLinkRecognition.parse('bilibili://video/170001'), [
      Uri.parse('bilibili://video/170001'),
    ]);
  });

  test('extracts standalone BV and av identifiers from ordinary text', () {
    expect(BiliLinkRecognition.parse('推荐 BV1xx411c7mD，再看 AV170001。'), [
      Uri.parse(video),
      Uri.parse('https://www.bilibili.com/video/av170001'),
    ]);
    expect(BiliLinkRecognition.parse('bv1xx411c7mD BV1xx411c7mD'), [
      Uri.parse(video),
    ]);
  });

  for (final input in [
    'https://@www.bilibili.com/video/BV1xx411c7mD',
    '',
    'ordinary text',
    'xBV1xx411c7mD',
    'BV1xx411c7mDx',
    'av0',
    'av9223372036854775808',
    'https://bilibili.com.evil.example/video/BV1xx411c7mD',
    'https://notbilibili.com/video/BV1xx411c7mD',
    'https://bilibili.com@evil.example/video/BV1xx411c7mD',
    'https://user:password@www.bilibili.com/video/BV1xx411c7mD',
    'https://www.bilibili.com:8443/video/BV1xx411c7mD',
    'https://bilibili.com./video/BV1xx411c7mD',
    'https://evil.example/video/BV1xx411c7mD',
    'file:///tmp/BV1xx411c7mD',
    'javascript:alert(1)',
    'data:text/html,<h1>test</h1>',
    'bilibili://authorize?auth_code=123',
    'bilibili://video:1234/170001',
    'https://passport.bilibili.com/h5-app/passport/login/scan?qrcode_key=0123456789abcdef0123456789abcdef',
    'https://passport.bilibili.com/x/passport-tv-login/h5/qrcode/auth?auth_code=0123456789abcdef0123456789abcdef',
    'https://account.bilibili.com/',
    'https://www.bilibili.com/video/BV1xx411c7mD\u0000',
    'https://www.bilibili.com/video/BV1xx411c7mD\u007f',
  ]) {
    test('does not recognize unsafe or unsupported input: $input', () {
      expect(BiliLinkRecognition.parse(input), isEmpty);
    });
  }

  for (final input in [
    'evil.b23.tv/abc123',
    'evil.www.bilibili.com/video/BV1xx411c7mD',
    'evil.example/BV1xx411c7mD',
    'evil.example/?id=BV1xx411c7mD',
  ]) {
    test(
      'does not salvage trusted fragments from bare untrusted URLs: $input',
      () {
        expect(BiliLinkRecognition.parse(input), isEmpty);
      },
    );
  }

  test('limits payload size before parsing and permits the exact boundary', () {
    final input =
        '$video${' ' * (BiliLinkRecognition.maxTextLength - video.length)}';
    expect(BiliLinkRecognition.parse(input), [Uri.parse(video)]);
    expect(BiliLinkRecognition.parse('$input '), isEmpty);
  });

  test('limits the number of distinct links offered by one payload', () {
    final input = List.generate(20, (i) => 'https://b23.tv/item$i').join('\n');
    final links = BiliLinkRecognition.parse(input);
    expect(links.length, 8);
    expect(links.last.path, '/item7');
  });
}
