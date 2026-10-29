import 'package:PiliPlus/utils/trusted_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('account URL policy', () {
    for (final url in [
      'https://bilibili.com',
      'https://www.bilibili.com/video/BV1xx411c7mD',
      'https://api.bilibili.com:443/x/web-interface/nav',
      'https://mall.bilibili.com/',
      'https://WWW.BILIBILI.COM/',
    ]) {
      test('accepts $url', () {
        expect(TrustedUrl.isBilibili(Uri.parse(url)), isTrue);
      });
    }

    for (final url in [
      'http://www.bilibili.com/',
      'https://bilibili.com.example.org/',
      'https://notbilibili.com/',
      'https://bilibili.com@evil.example/',
      'https://user:password@www.bilibili.com/',
      'https://www.bilibili.com:8443/',
      'https://bilibili.com./',
      'https://b23.tv/abc',
      'file:///www.bilibili.com/',
      'javascript:alert(1)',
      '//www.bilibili.com/',
      '/video/BV1xx411c7mD',
    ]) {
      test('rejects $url', () {
        expect(TrustedUrl.isBilibili(Uri.parse(url)), isFalse);
      });
    }
  });

  group('scanned links', () {
    test('normalizes video IDs and surrounding whitespace', () {
      expect(
        TrustedUrl.scanLink('  BV1xx411c7mD\n')?.toString(),
        'https://www.bilibili.com/video/BV1xx411c7mD',
      );
      expect(
        TrustedUrl.scanLink('AV170001')?.toString(),
        'https://www.bilibili.com/video/av170001',
      );
    });

    for (final value in [
      '',
      'BV1xx411c7m',
      'BV1xx411c7mDx',
      'bv1xx411c7mD',
      'BV1xx411c7m!',
      'av',
      'av-1',
      'av1x',
      'ordinary text',
      'javascript:alert(1)',
      'data:text/html,<h1>test</h1>',
      'file:///tmp/image.png',
      'bilibili://video/170001',
      'https://user:password@www.bilibili.com/',
      'https://',
      'https://www.bilibili.com/video/one two',
      'https://www.bilibili.com/\u0000video',
      'https://www.bilibili.com/\u007fvideo',
    ]) {
      test('does not open ${value.replaceAll('\n', r'\n')}', () {
        expect(TrustedUrl.scanLink(value), isNull);
      });
    }

    test('external web links stay external rather than trusted', () {
      for (final value in [
        'https://bilibili.com.example.org/video/BV1xx411c7mD',
        'https://b23.tv/abc',
        'http://www.bilibili.com/',
        'https://www.bilibili.com:8443/',
      ]) {
        final uri = TrustedUrl.scanLink(value);
        expect(uri, isNotNull);
        expect(TrustedUrl.isBilibili(uri!), isFalse);
      }
    });

    test('enforces the maximum scanned URL length', () {
      const prefix = 'https://example.org/';
      final accepted = prefix + 'a' * (8192 - prefix.length);
      expect(TrustedUrl.scanLink(accepted), isNotNull);
      expect(TrustedUrl.scanLink('${accepted}a'), isNull);
    });
  });

  group('note bridge URL policy', () {
    test('accepts only the HTTPS main-site note page', () {
      final uri = Uri.parse('https://www.bilibili.com/h5/note-app?oid=170001');
      expect(TrustedUrl.isBilibiliNote(uri), isTrue);
      expect(TrustedUrl.noteVideoId(uri), 170001);
      expect(TrustedUrl.isBilibiliNote(null), isFalse);
      expect(TrustedUrl.noteVideoId(null), isNull);
    });

    for (final url in [
      'http://www.bilibili.com/h5/note-app?oid=1',
      'https://www.bilibili.com.example.org/h5/note-app?oid=1',
      'https://mall.bilibili.com/h5/note-app?oid=1',
      'https://user@www.bilibili.com/h5/note-app?oid=1',
      'https://www.bilibili.com:8443/h5/note-app?oid=1',
      'https://www.bilibili.com/h5/note-app-other?oid=1',
      'https://www.bilibili.com/h5/note-app/child?oid=1',
      'https://www.bilibili.com/video/BV1xx411c7mD?oid=1',
    ]) {
      test('rejects bridge access from $url', () {
        final uri = Uri.parse(url);
        expect(TrustedUrl.isBilibiliNote(uri), isFalse);
        expect(TrustedUrl.noteVideoId(uri), isNull);
      });
    }

    for (final query in [
      '',
      '?oid=',
      '?oid=abc',
      '?oid=0',
      '?oid=-1',
      '?oid=%FF',
    ]) {
      test('ignores invalid video ID $query without throwing', () {
        expect(
          TrustedUrl.noteVideoId(
            Uri.parse('https://www.bilibili.com/h5/note-app$query'),
          ),
          isNull,
        );
      });
    }
  });
}
