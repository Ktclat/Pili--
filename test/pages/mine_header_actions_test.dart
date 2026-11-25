import 'dart:typed_data';

import 'package:PiliPlus/models/user/info.dart';
import 'package:PiliPlus/pages/link_recognition/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/view.dart';
import 'package:PiliPlus/pages/scan/view.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Box<T> extends Fake implements Box<T> {
  final data = <String, T>{};

  @override
  T? get(dynamic key, {T? defaultValue}) => data[key] ?? defaultValue;

  @override
  bool get isNotEmpty => data.isNotEmpty;
}

void main() {
  testWidgets('Mine keeps scan and link recognition in its top-right menu', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 680)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    GStorage.userInfo = _Box<UserInfoData>();
    GStorage.setting = _Box<dynamic>()
      ..data.addAll({
        SettingBoxKey.autoUpdate: false,
        SettingBoxKey.mineTabs: [],
        SettingBoxKey.navBarSort: [2],
      });
    GStorage.reply = _Box<Uint8List>();
    Accounts.account = _Box<LoginAccount>();
    Get.testMode = true;
    addTearDown(Get.reset);
    Get.put(AccountService()).isLogin.value = true;
    Get.put(MainController());

    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: MinePage(showBackBtn: true)),
        getPages: [
          GetPage(name: '/scan', page: () => const ScanPage()),
          GetPage(
            name: '/recognizeLink',
            page: () => const LinkRecognitionPage(),
          ),
          GetPage(
            name: '/myReply',
            page: () => const Scaffold(body: Text('评论记录页面')),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final more = find.byTooltip('更多操作');
    final list = find.byType(ListView);
    for (final label in ['扫一扫', '识别链接']) {
      expect(
        find.descendant(of: list, matching: find.text(label)),
        findsNothing,
      );
    }
    expect(find.byTooltip('消息'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byTooltip('评论记录'), findsNothing);
    expect(tester.getSize(more), const Size.square(48));
    expect(tester.getSemantics(more).flagsCollection.isButton, isTrue);
    expect(
      tester.getCenter(more).dx,
      greaterThan(tester.getCenter(find.byTooltip('设置')).dx),
    );

    Future<void> select(String label) async {
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('扫一扫'), findsOneWidget);
      expect(find.text('识别链接'), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(more, findsOneWidget);
    }

    await select('扫一扫');
    expect(find.byType(ScanPage), findsOneWidget);
    await back();
    await select('评论记录');
    expect(find.text('评论记录页面'), findsOneWidget);
    await back();

    tester.view.physicalSize = const Size(680, 320);
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    for (final label in [
      '搜索',
      '消息',
      '评论记录',
      '进入无痕模式',
      '切换账号',
      '切换至浅色主题',
      '设置',
    ]) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    await select('识别链接');
    expect(find.byType(LinkRecognitionPage), findsOneWidget);
    await back();
    expect(tester.takeException(), isNull);
  });
}
