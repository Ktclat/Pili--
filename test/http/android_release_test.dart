import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/http/android_release.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/release_info.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _Settings extends Fake implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}

class _Attachment extends Fake implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  var text = '{"release_tag":"v0.6.3"}';
  var status = 200;
  var compressed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = utf8.encode(text);
    return ResponseBody.fromBytes(
      compressed ? gzip.encode(bytes) : bytes,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/octet-stream'],
        if (compressed) Headers.contentEncodingHeader: ['gzip'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final asset = {
    'name': 'BUILD_INFO.json',
    'state': 'uploaded',
    'digest':
        'sha256:${sha256.convert(utf8.encode('{"release_tag":"v0.6.3"}'))}',
    'browser_download_url': 'https://example.org/foreign.json',
  };
  ReleaseInfo latest(List<Object> assets) => ReleaseInfo.fromLatest({
    'tag_name': 'v0.6.3',
    'draft': false,
    'prerelease': false,
    'assets': assets,
  })!;

  late _Attachment adapter;
  setUpAll(() {
    GStorage.setting = _Settings();
    Request();
  });
  setUp(() => Request.dio.httpClientAdapter = adapter = _Attachment());
  tearDownAll(() => Request.dio.close());

  test(
    'loads the tagged JSON attachment anonymously, including binary MIME',
    () async {
      adapter.compressed = true;
      expect(await loadAndroidBuildInfo(latest([asset])), {
        'release_tag': 'v0.6.3',
      });
      final request = adapter.requests.single;
      expect(
        request.uri.toString(),
        'https://github.com/Ktclat/Pili--/releases/download/v0.6.3/BUILD_INFO.json',
      );
      expect(request.extra['account'], isA<NoAccount>());
      expect(
        request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(
        request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(await loadAndroidBuildInfo(latest([])), isNull);
      expect(adapter.requests, hasLength(1));
    },
  );

  test('rejects partial, invalid and missing metadata without caching a failed attempt', () async {
    final release = latest([asset]);
    adapter.status = HttpStatus.partialContent;
    await expectLater(
      loadAndroidBuildInfo(release),
      throwsA(isA<HttpException>()),
    );
    adapter
      ..status = HttpStatus.ok
      ..text = '<html>Unavailable</html>';
    await expectLater(loadAndroidBuildInfo(release), throwsFormatException);
    adapter.text = '{"release_tag":"v0.6.4"}';
    await expectLater(loadAndroidBuildInfo(release), throwsFormatException);
    adapter.text = '{"release_tag":"v0.6.3"}';
    expect(await loadAndroidBuildInfo(release), {'release_tag': 'v0.6.3'});
  });
}
