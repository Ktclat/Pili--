import 'dart:async';

import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models_new/live/live_trace/data.dart';
import 'package:PiliPlus/pages/fans_medal/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _Box extends Fake implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) {
    if (key == LocalCacheKey.timeStamp) {
      return DateTime.now().millisecondsSinceEpoch;
    }
    if (key == LocalCacheKey.mixinKey) return 'fake-cache-key';
    return defaultValue;
  }
}

LoginAccount _account(int mid) => LoginAccount(
  BiliCookieJar.fromJson({
    'DedeUserID': '$mid',
    'bili_jct': 'csrf-$mid',
  }),
  null,
  null,
  null,
  'device-$mid',
);

void main() {
  final main = _account(1);
  final heartbeat = _account(2);
  final sent = <RequestOptions>[];
  setUpAll(() async {
    final bootstrap = Completer<RequestOptions>();
    GStorage.setting = _Box();
    GStorage.localCache = _Box();
    Request();
    Request.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!bootstrap.isCompleted &&
              options.path == '/x/frontend/finger/spi') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'code': 0,
                  'data': {'b_3': 'guest-3', 'b_4': 'guest-4'},
                },
              ),
            );
            bootstrap.complete(options);
            return;
          }
          sent.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'code': 0,
                'data': <String, dynamic>{
                  'timestamp': 1,
                  'secret_key': 'test',
                  'secret_rule': [0],
                },
              },
            ),
          );
        },
      ),
    );
    // Initializing account roles creates the anonymous device identity once.
    AnonymousAccount();
    expect((await bootstrap.future).extra['account'], isA<NoAccount>());
  });
  setUp(() {
    sent.clear();
    Accounts.accountMode[AccountType.main.index] = main;
    Accounts.accountMode[AccountType.heartbeat.index] = heartbeat;
  });
  test('trace signs and binds the heartbeat account and rechecks eligibility after signing', () async {
    final req = LiveTraceReq(
      parentAreaId: 1,
      areaId: 2,
      roomId: 3,
      liveBuvid: 'device',
      ruid: 4,
    );
    final token = CancelToken();
    final res = await LiveHttp.liveTraceE(
      traceReq: req,
      heartbeat: heartbeat,
      token: token,
      isCurrent: () => true,
    );
    expect(res.isSuccess, isTrue);
    expect(sent.map((options) => options.path), [Api.liveTraceE]);
    expect(sent.single.extra['account'], same(heartbeat));
    expect(sent.single.queryParameters['csrf'], heartbeat.csrf);
    expect(sent.single.cancelToken, same(token));
    var current = true;
    final pending = LiveHttp.liveTraceX(
      traceReq: req,
      traceResp: res.data,
      heartbeat: heartbeat,
      token: token,
      isCurrent: () => current,
    );
    current = false;
    expect((await pending).isSuccess, isFalse);
    expect(sent, hasLength(1));
  });

  test(
    'medal requests use the main session and stale controls refuse changes',
    () async {
      await LiveHttp.userMedalInfo(account: main, upId: 9);
      expect(sent.single.path, Api.userMedalInfo);
      expect(sent.single.queryParameters['uid'], main.mid);
      expect(sent.single.extra['account'], same(main));
      await LiveHttp.wearFansMedal(account: main, medalId: 8);
      expect(sent.last.extra['account'], same(main));
      expect(sent.last.data['csrf'], main.csrf);
      final controller = FansMedalController(main);
      Accounts.accountMode[AccountType.main.index] = _account(main.mid);
      expect(
        await controller.setConfigPlus(key: 'old-setting', status: true),
        isFalse,
      );
      expect((await controller.customGetData()).isSuccess, isFalse);
      expect(sent, hasLength(2));
    },
  );
}
