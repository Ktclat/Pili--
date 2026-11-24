import 'dart:async';

import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models_new/live/live_fans_medal/item.dart';
import 'package:PiliPlus/models_new/live/live_trace/data.dart';
import 'package:PiliPlus/pages/fans_medal/controller.dart';
import 'package:PiliPlus/pages/fans_medal/view.dart';
import 'package:PiliPlus/pages/live_room/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' show GetxController;
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;

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

class _RoomLikes extends GetxController with LiveLikeMixin {
  _RoomLikes(this.heartbeat);

  @override
  final Account heartbeat;
  @override
  int get roomId => 42;
  @override
  int get ruid => 99;
}

void main() {
  final main = _account(1);
  final heartbeat = _account(2);
  final sent = <RequestOptions>[];
  final pendingLikes = <RequestInterceptorHandler>[];
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
          if (options.path == Api.liveLikeReport) {
            pendingLikes.add(handler);
            return;
          }
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
    pendingLikes.clear();
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
    'room entry uses the same watching account for cookies and CSRF',
    () async {
      final entry = VideoHttp.roomEntryAction(roomId: 42, account: heartbeat);
      Accounts.accountMode[AccountType.heartbeat.index] = main;
      await entry;
      final request = sent.single;
      expect(request.path, Api.roomEntryAction);
      expect(request.extra['account'], same(heartbeat));
      expect(request.queryParameters['csrf'], heartbeat.csrf);
    },
  );

  testWidgets(
    'rapid likes form independent batches with the watching account',
    (tester) async {
      final room = _RoomLikes(heartbeat)
        ..onLikeTap()
        ..onLikeTap();
      await tester.pump(const Duration(milliseconds: 800));
      expect(sent, hasLength(1));
      expect(room.likeClickTime.value, 0);
      expect(sent.first.data['click_time'], 2);
      expect(sent.first.data['uid'], heartbeat.mid);
      expect(sent.first.data['csrf'], heartbeat.csrf);
      expect(sent.first.extra['account'], same(heartbeat));

      room.onLikeTap();
      expect(room.likeClickTime.value, 1);
      await tester.pump(const Duration(milliseconds: 800));
      expect(sent.map((o) => o.data['click_time']), [2, 1]);

      room.onDelete();
      for (var i = pendingLikes.length - 1; i >= 0; i--) {
        pendingLikes[i].resolve(
          Response(
            requestOptions: sent[i],
            statusCode: 200,
            data: {'code': 0},
          ),
        );
      }
      await tester.pump();
    },
  );

  testWidgets(
    'likes are dropped on close, account replacement or during signing',
    (tester) async {
      final room = _RoomLikes(heartbeat)..onLikeTap();
      Accounts.accountMode[AccountType.heartbeat.index] = _account(
        heartbeat.mid,
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(sent, isEmpty);

      Accounts.accountMode[AccountType.heartbeat.index] = heartbeat;
      room
        ..onLikeTap()
        ..onDelete();
      await tester.pump(const Duration(milliseconds: 800));
      expect(sent, isEmpty);

      final signing = LiveHttp.liveLikeReport(
        account: heartbeat,
        clickTime: 1,
        roomId: 42,
      );
      Accounts.accountMode[AccountType.heartbeat.index] = main;
      expect((await signing).isSuccess, isFalse);
      expect(sent, isEmpty);
    },
  );

  testWidgets(
    'medal management shows supported actions and toggles the worn medal',
    (tester) async {
      final item = FansMedalItem.fromJson({
        'medal': <String, dynamic>{'wearing_status': 0},
        'anchor_info': <String, dynamic>{'nick_name': '主播'},
        'uinfo_medal': <String, dynamic>{
          'id': 8,
          'ruid': 9,
          'level': 1,
          'name': '勋章',
          'v2_medal_color_start': '#123456FF',
          'v2_medal_color_text': '#FFFFFFFF',
        },
      });
      FansMedalController.forAccount(main)
        ..isEnd = true
        ..loadingState.value = Success([item]);
      await tester.pumpWidget(const MaterialApp(home: FansMedalPage()));
      expect(find.byTooltip('展示设置'), findsOneWidget);
      expect(find.text('删除'), findsNothing);
      await tester.tap(find.text('佩戴'));
      await tester.pumpAndSettle();
      expect(find.text('取消佩戴'), findsOneWidget);
      await tester.tap(find.text('取消佩戴'));
      await tester.pumpAndSettle();
      expect(find.text('佩戴'), findsOneWidget);
      expect(sent.map((r) => r.path), [
        Api.wearFansMedal,
        Api.takeOffFansMedal,
      ]);
    },
  );

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
