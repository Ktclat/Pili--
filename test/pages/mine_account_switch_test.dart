import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/user/info.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/login_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

LoginAccount _account(int id) => LoginAccount(
  BiliCookieJar.fromJson({'DedeUserID': '$id', 'bili_jct': 'csrf-$id'}),
  null,
  null,
  null,
  'device-$id',
);

void main() {
  final a = _account(1);
  final b = _account(2);
  late Directory directory;
  late MineController mine;
  late AccountService service;
  late Completer<RequestOptions> started;
  late Completer<Map<String, Object?>> reply;
  void select(Account account) {
    Accounts.accountMode[AccountType.main.index] = account;
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pili-mine-account-');
    Hive.init(directory.path);
    GStorage.regAdapter();
    GStorage.setting = await Hive.openBox('settings');
    GStorage.localCache = await Hive.openBox('cache');
    GStorage.userInfo = await Hive.openBox<UserInfoData>('profiles');
    Accounts.account = await Hive.openBox<LoginAccount>('accounts');
    Request();
    Request.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.path == '/x/frontend/finger/spi') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'code': 0,
                  'data': {'b_3': 'guest3', 'b_4': 'guest4'},
                },
              ),
            );
            return;
          }
          started.complete(options);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: await reply.future,
            ),
          );
        },
      ),
    );
    select(b);
    service = Get.put(AccountService());
    mine = MineController();
  });

  tearDownAll(() async {
    Request.dio.close();
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  setUp(() async {
    started = Completer();
    reply = Completer();
    await a.onChange();
    await b.onChange();
    final bInfo = UserInfoData(mid: 2, uname: 'B', face: 'b');
    await GStorage.userInfo.put('userInfoCache', bInfo);
    mine.userInfo.value = bInfo;
    service.face.value = 'b';
    service.isLogin.value = true;
    GlobalData().coins = 20;
    select(a);
  });

  for (final entry in {
    'expired session': <String, Object?>{'code': -101, 'message': '账号未登录'},
    'logged out': <String, Object?>{
      'code': 0,
      'data': {'isLogin': false},
    },
    'signed-in profile': <String, Object?>{
      'code': 0,
      'data': {'isLogin': true, 'mid': 1, 'money': 1, 'face': 'a'},
    },
  }.entries) {
    test(
      'late ${entry.key} on Mine cannot change the newly selected account',
      () async {
        final refresh = mine.queryUserInfo();
        final request = await started.future;
        expect(request.path, Api.userInfo);
        expect(request.extra['account'], same(a));
        select(b);
        reply.complete(entry.value);
        await refresh;
        expect(Accounts.main, same(b));
        expect(Accounts.account.containsKey('2'), isTrue);
        expect(mine.userInfo.value.mid, b.mid);
        expect(Pref.userInfoCache?.mid, b.mid);
        expect(service.face.value, 'b');
        expect(service.isLogin.value, isTrue);
        expect(GlobalData().coins, 20);
      },
    );
  }

  test(
    'login validation after switching accounts does not delete the old session',
    () async {
      final pending = LoginUtils.onLoginMain();
      expect((await started.future).extra['account'], same(a));
      select(b);
      reply.complete({'code': -101, 'message': '账号未登录'});
      await pending;
      expect(Accounts.account.containsKey('1'), isTrue);
      expect(Accounts.account.containsKey('2'), isTrue);
    },
  );

  test('cached profile is visible only to its owner', () {
    expect(Pref.userInfoCache, isNull);
    select(b);
    expect(Pref.userInfoCache?.uname, 'B');
    select(AnonymousAccount());
    expect(Pref.userInfoCache, isNull);
  });

  test('previous account statistics cannot overwrite a new profile', () async {
    final pending = mine.queryUserStatOwner();
    expect((await started.future).extra['account'], same(a));
    select(b);
    reply.complete({
      'code': 0,
      'data': {'following': 35},
    });
    await pending;
    expect(mine.userStat.value.following, isNull);
  });
}
