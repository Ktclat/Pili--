import 'dart:typed_data';

import 'package:PiliPlus/models/user/info.dart';
import 'package:PiliPlus/pages/link_recognition/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/view.dart';
import 'package:PiliPlus/pages/scan/view.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/header_action_preferences.dart';
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
  Future<void> put(dynamic key, T value) async {
    data[key as String] = value;
  }

  @override
  bool get isNotEmpty => data.isNotEmpty;
}

void main() {
  final settings = _Box<dynamic>();
  late MainController main;

  setUpAll(() {
    GStorage.userInfo = _Box<UserInfoData>();
    GStorage.setting = settings;
    GStorage.reply = _Box<Uint8List>();
    Accounts.account = _Box<LoginAccount>();
  });
  setUp(() {
    settings.data
      ..clear()
      ..addAll({
        SettingBoxKey.autoUpdate: false,
        SettingBoxKey.mineTabs: [],
        SettingBoxKey.msgUnReadTypeV2: [],
        SettingBoxKey.navBarSort: [2],
      });
    Get.testMode = true;
    Get.put(AccountService()).isLogin.value = true;
  });
  tearDown(Get.reset);

  Future<void> mount(
    WidgetTester tester,
    Size size, {
    bool withHome = false,
  }) async {
    if (withHome) settings.data[SettingBoxKey.navBarSort] = [0, 2];
    main = Get.put(MainController());
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
            name: '/setting',
            page: () => const Scaffold(body: Text('设置页面')),
          ),
          GetPage(
            name: '/search',
            page: () => const Scaffold(body: Text('搜索页面')),
          ),
          GetPage(
            name: '/whisper',
            page: () => const Scaffold(body: Text('消息页面')),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Mine defaults to scan and link recognition in its top-right menu',
    (
      tester,
    ) async {
      await mount(tester, const Size(320, 680));
      final more = find.byTooltip('更多操作');
      final list = find.byType(ListView);
      for (final label in ['扫一扫', '识别链接']) {
        expect(
          find.descendant(of: list, matching: find.text(label)),
          findsNothing,
        );
      }
      expect(find.byTooltip('消息'), findsOneWidget);
      expect(find.byTooltip('评论记录'), findsOneWidget);
      expect(find.byTooltip('设置'), findsNothing);
      expect(tester.getSize(more), const Size.square(48));
      expect(tester.getSemantics(more).flagsCollection.isButton, isTrue);
      expect(
        tester.getCenter(more).dx,
        greaterThan(tester.getCenter(find.byTooltip('评论记录')).dx),
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
      await select('设置');
      expect(find.text('设置页面'), findsOneWidget);
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
    },
  );

  testWidgets(
    'Mine applies edited placement and order and keeps hidden tools usable',
    (
      tester,
    ) async {
      await mount(tester, const Size(680, 850), withHome: true);
      expect(find.byTooltip('搜索'), findsNothing);
      final more = find.byTooltip('更多操作');
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑按钮'));
      await tester.pumpAndSettle();

      final search = find.widgetWithText(CheckboxListTile, '搜索');
      await tester.ensureVisible(search);
      expect(tester.widget<CheckboxListTile>(search).value, isFalse);
      await tester.tap(search);
      await tester.pumpAndSettle();
      final scan = find.widgetWithText(CheckboxListTile, '扫一扫');
      await tester.ensureVisible(scan);
      expect(tester.widget<CheckboxListTile>(scan).value, isFalse);
      await tester.tap(scan);
      await tester.pumpAndSettle();
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(find.byTooltip('扫一扫'), findsOneWidget);
      expect(find.byTooltip('识别链接'), findsNothing);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      expect(find.text('搜索页面'), findsOneWidget);
      Get.back<void>();
      await tester.pumpAndSettle();

      final entries = HeaderActionPreferences.read(HeaderActionPage.mine);
      await HeaderActionPreferences.save(HeaderActionPage.mine, [
        (action: HeaderAction.recognizeLink, pinned: true),
        (action: HeaderAction.scan, pinned: true),
        for (final entry in entries)
          if (entry.action != HeaderAction.scan &&
              entry.action != HeaderAction.recognizeLink)
            (
              action: entry.action,
              pinned: entry.action != HeaderAction.messages,
            ),
      ]);
      tester.view.physicalSize = const Size(320, 680);
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byTooltip('识别链接')).dx,
        lessThan(tester.getCenter(find.byTooltip('扫一扫')).dx),
      );
      expect(find.byTooltip('消息'), findsNothing);
      await tester.tap(find.byTooltip('识别链接'));
      await tester.pumpAndSettle();
      expect(find.byType(LinkRecognitionPage), findsOneWidget);
      Get.back<void>();
      await tester.pumpAndSettle();

      main.msgUnReadCount.value = '2';
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: more, matching: find.text('2')),
        findsOneWidget,
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('扫一扫'), findsNothing);
      expect(find.text('识别链接'), findsNothing);
      expect(find.text('设置'), findsOneWidget);
      await tester.tap(find.text('消息'));
      await tester.pumpAndSettle();
      expect(find.text('消息页面'), findsOneWidget);
      expect(main.msgUnReadCount.value, isNull);
      Get.back<void>();
      await tester.pumpAndSettle();

      Get.find<AccountService>().isLogin.value = false;
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('消息'), findsNothing);
      expect(find.text('编辑按钮'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
