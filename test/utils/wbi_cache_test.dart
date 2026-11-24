import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/wbi_sign.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  const first = '0123456789abcdef0123456789abcdef';
  const second = 'fedcba9876543210fedcba9876543210';
  const response = {
    'data': {
      'wbi_img': {
        'img_url': 'https://i.example/img/$first.png',
        'sub_url': 'https://i.example/img/$second.png',
      },
    },
  };
  final expectedKey = WbiSign.getMixinKey(first + second);
  final requests = <String>[];
  late Directory dir;
  late FutureOr<Object> Function() reply;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('pili-wbi-cache');
    Hive.init(dir.path);
    GStorage.localCache = await Hive.openBox('local');
    GStorage.setting = await Hive.openBox('setting');
    Request();
    Request.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add(options.path);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: await reply(),
            ),
          );
        },
      ),
    );
  });
  setUp(() async {
    await GStorage.localCache.clear();
    requests.clear();
    reply = () => response;
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('a key from the same day of an earlier month is expired', () async {
    final now = DateTime.now();
    final previous = DateTime(now.year - 1, DateTime.december, now.day);
    await GStorage.localCache.putAll({
      LocalCacheKey.timeStamp: previous.millisecondsSinceEpoch,
      LocalCacheKey.mixinKey: 'old-key',
    });

    expect(await WbiSign.getWbiKeys(), expectedKey);
    expect(await WbiSign.getWbiKeys(), expectedKey);
    expect(requests, [Api.userInfo]);
    expect(GStorage.localCache.get(LocalCacheKey.mixinKey), expectedKey);
  });

  test('a failed refresh leaves the stale pair intact and can retry', () async {
    await GStorage.localCache.putAll({
      LocalCacheKey.timeStamp: 0,
      LocalCacheKey.mixinKey: 'stale-key',
    });
    reply = () => {'code': -1};
    expect(await WbiSign.getWbiKeys(), isEmpty);
    expect(GStorage.localCache.get(LocalCacheKey.timeStamp), 0);
    expect(GStorage.localCache.get(LocalCacheKey.mixinKey), 'stale-key');

    reply = () => response;
    expect(await WbiSign.getWbiKeys(), expectedKey);
    expect(requests, [Api.userInfo, Api.userInfo]);
  });

  test(
    'concurrent callers share a refresh after a failed cold start',
    () async {
      reply = () => {'code': -1};
      expect(await WbiSign.getWbiKeys(), isEmpty);
      final entered = Completer<void>();
      final ready = Completer<Object>();
      reply = () {
        if (!entered.isCompleted) entered.complete();
        return ready.future;
      };
      final pending = Future.wait([
        for (var i = 0; i < 4; i++) Future.sync(WbiSign.getWbiKeys),
      ]);
      await entered.future;
      expect(GStorage.localCache.get(LocalCacheKey.timeStamp), isNull);
      ready.complete(response);
      expect(await pending, List.filled(4, expectedKey));
      expect(requests, [Api.userInfo, Api.userInfo]);
    },
  );
}
