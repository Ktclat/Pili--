import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/url_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <RequestOptions>[];
  String? location;
  setUpAll(() {
    Request.dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response<void>(
                requestOptions: options,
                statusCode: 302,
                headers: Headers.fromMap({
                  if (location != null) 'location': [location!],
                }),
              ),
            );
          },
        ),
      );
  });
  setUp(() {
    requests.clear();
    location = null;
  });
  tearDownAll(() => Request.dio.close());

  test('short link HEAD preserves the path and encoded query', () async {
    const source = 'https://b23.tv/watch?token=a%2Fb&key=1';
    location = 'other?id=x%2Fy';
    expect(
      await UrlUtils.parseRedirectUrl(source),
      'https://b23.tv/other?id=x%2Fy',
    );
    final request = requests.single;
    expect(request.uri.toString(), source);
    expect(request.method, 'HEAD');
    expect(request.followRedirects, isFalse);
    expect(request.extra['account'], isA<AnonymousAccount>());
  });

  test(
    'article lookup keeps its explicit directory for relative redirects',
    () async {
      location = '../new/';
      expect(
        await UrlUtils.parseRedirectUrl('https://www.bilibili.com/read/cv1/'),
        'https://www.bilibili.com/read/new/',
      );
    },
  );

  test(
    'native routes reject lookalike domains and nonstandard origins',
    () async {
      for (final url in [
        'https://notbilibili.com/video/BV17x411w7KC',
        'https://bilibili.com.example.org/video/BV17x411w7KC',
        'https://fakeb23.tv/link',
        'https://b23.tv:8443/link',
        'https://login@b23.tv/link',
      ]) {
        expect(
          await PiliScheme.routePush(Uri.parse(url), selfHandle: true),
          isFalse,
        );
      }
      expect(requests, isEmpty);
    },
  );

  test('short link redirect destinations must be web links', () async {
    for (final target in ['bilibili://download', 'javascript:void(0)', '']) {
      location = target;
      expect(await UrlUtils.parseRedirectUrl('https://b23.tv/watch'), isNull);
    }
    location = 'https://unrelated.example/video/BV17x411w7KC';
    expect(
      await PiliScheme.routePush(
        Uri.parse('https://b23.tv/watch'),
        selfHandle: true,
      ),
      isFalse,
    );
  });

  test(
    'content routes consume login links without opening a web page',
    () async {
      const web = 'https://account.bilibili.com/h5/account-h5/auth/scan-web';
      for (final url in [
        '$web?qrcode_key=0123456789abcdef0123456789abcdef',
        '$web?qrcode_key=invalid',
        'bilibili://auth/launch?callback=test',
      ]) {
        expect(
          await PiliScheme.routePushFromUrl(url, selfHandle: true),
          isTrue,
        );
      }
      expect(requests, isEmpty);

      location = '$web?qrcode_key=invalid';
      expect(
        await PiliScheme.routePushFromUrl(
          'https://b23.tv/abc',
          selfHandle: true,
        ),
        isTrue,
      );
      expect(requests.single.uri.host, 'b23.tv');
    },
  );
}
