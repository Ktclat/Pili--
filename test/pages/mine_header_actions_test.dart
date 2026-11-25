import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/models/user/info.dart';
import 'package:PiliPlus/pages/link_recognition/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/view.dart';
import 'package:PiliPlus/pages/scan/view.dart';
import 'package:PiliPlus/pages/setting/view.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/header_action_preferences.dart';
import 'package:PiliPlus/utils/path_utils.dart';
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
  bool get isEmpty => data.isEmpty;

  @override
  bool get isNotEmpty => data.isNotEmpty;
}

void main() {
  final settings = _Box<dynamic>();
  late MainController main;

  setUpAll(() {
    final directory = Directory.systemTemp.createTempSync('mine-header-test');
    appSupportDirPath = directory.path;
    addTearDown(() => directory.deleteSync(recursive: true));
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
    bool showBack = true,
  }) async {
    if (withHome) settings.data[SettingBoxKey.navBarSort] = [0, 2];
    main = Get.put(MainController());
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(body: MinePage(showBackBtn: showBack)),
        getPages: [
          GetPage(name: '/scan', page: () => const ScanPage()),
          GetPage(
            name: '/recognizeLink',
            page: () => const LinkRecognitionPage(),
          ),
          GetPage(name: '/setting', page: () => const SettingPage()),
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

  testWidgets('Mine offers its default tools directly and hides recognition', (
    tester,
  ) async {
    await mount(tester, const Size(320, 680));
    final scan = find.byTooltip('扫一扫');
    final messages = find.byTooltip('消息');
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(find.byTooltip('识别链接'), findsNothing);
    expect(find.text('识别链接'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
    expect(scan.hitTestable(), findsOneWidget);
    expect(tester.getSize(scan), const Size.square(48));
    expect(tester.getSemantics(scan).flagsCollection.isButton, isTrue);
    expect(
      tester.getCenter(scan).dy,
      greaterThan(tester.getCenter(messages).dy),
    );
    expect(
      tester.getBottomLeft(scan).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(ListView)).dy),
    );

    await tester.tap(scan);
    await tester.pumpAndSettle();
    expect(find.byType(ScanPage), findsOneWidget);
    Get.back<void>();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(680, 320);
    await tester.pumpAndSettle();
    expect(tester.getCenter(scan).dy, tester.getCenter(messages).dy);
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Mine updates visible tools from Settings and keeps their order',
    (
      tester,
    ) async {
      await mount(tester, const Size(680, 850), withHome: true);
      expect(find.byTooltip('搜索'), findsNothing);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('外观设置'), 160);
      await tester.tap(find.text('外观设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('右上角按钮'), 160);
      await tester.tap(find.text('右上角按钮'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, '我的'));
      await tester.pumpAndSettle();

      Future<void> toggle(String label, bool previous) async {
        final checkbox = find.widgetWithText(CheckboxListTile, label);
        await tester.ensureVisible(checkbox);
        expect(tester.widget<CheckboxListTile>(checkbox).value, previous);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
      }

      await toggle('搜索', false);
      await toggle('扫一扫', true);
      await toggle('识别链接', false);
      Get.until((route) => route.isFirst);
      await tester.pumpAndSettle();
      expect(find.byTooltip('更多操作'), findsNothing);
      expect(find.byTooltip('扫一扫'), findsNothing);
      await tester.tap(find.byTooltip('识别链接'));
      await tester.pumpAndSettle();
      expect(find.byType(LinkRecognitionPage), findsOneWidget);
      Get.back<void>();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      expect(find.text('搜索页面'), findsOneWidget);
      Get.back<void>();
      await tester.pumpAndSettle();

      final entries = HeaderActionPreferences.read(.mine);
      await HeaderActionPreferences.save(.mine, [
        (action: .recognizeLink, pinned: true),
        (action: .scan, pinned: true),
        for (final entry in entries)
          if (entry.action != .recognizeLink && entry.action != .scan)
            (action: entry.action, pinned: entry.action != .messages),
      ]);
      tester.view.physicalSize = const Size(320, 680);
      main.msgUnReadCount.value = '2';
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byTooltip('识别链接')).dx,
        lessThan(tester.getCenter(find.byTooltip('扫一扫')).dx),
      );
      expect(find.byTooltip('消息'), findsNothing);
      expect(find.text('2'), findsNothing);
      expect(find.byTooltip('更多操作'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'All available tools stay reachable when Mine wraps on narrow screens',
    (
      tester,
    ) async {
      await HeaderActionPreferences.save(.mine, [
        for (final entry in HeaderActionPreferences.read(.mine))
          (action: entry.action, pinned: true),
      ]);
      // Nine actions plus the back button, with 8 dp padding on either side.
      await mount(tester, const Size(496, 750));
      final back = find.byType(BackButton);
      final recognize = find.byTooltip('识别链接');
      expect(tester.getCenter(recognize).dy, tester.getCenter(back).dy);
      tester.view.physicalSize = const Size(495, 750);
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(recognize).dy,
        greaterThan(tester.getCenter(back).dy),
      );
      expect(recognize.hitTestable(), findsOneWidget);
      expect(find.byTooltip('更多操作'), findsNothing);

      main.msgUnReadCount.value = '2';
      await tester.pumpAndSettle();
      final messages = find.byTooltip('消息');
      expect(
        find.descendant(of: messages, matching: find.text('2')),
        findsOneWidget,
      );
      await tester.tap(messages);
      await tester.pumpAndSettle();
      expect(find.text('消息页面'), findsOneWidget);
      expect(main.msgUnReadCount.value, isNull);
      Get.back<void>();
      await tester.pumpAndSettle();
      Get.find<AccountService>().isLogin.value = false;
      await tester.pumpAndSettle();
      expect(messages, findsNothing);
      expect(tester.getCenter(recognize).dy, tester.getCenter(back).dy);

      tester.view.physicalSize = const Size(300, 180);
      await tester.pumpAndSettle();
      await tester.ensureVisible(recognize);
      await tester.pumpAndSettle();
      expect(recognize.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(recognize).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(ListView)).dy),
      );
      await tester.tap(recognize);
      await tester.pumpAndSettle();
      expect(find.byType(LinkRecognitionPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mine still opens Settings from its body when every tool is hidden',
    (
      tester,
    ) async {
      await HeaderActionPreferences.save(.mine, [
        for (final entry in HeaderActionPreferences.read(.mine))
          (action: entry.action, pinned: false),
      ]);
      await mount(tester, const Size(320, 680), showBack: false);
      for (final label in ['扫一扫', '识别链接', '消息', '设置', '更多操作']) {
        expect(find.byTooltip(label), findsNothing);
      }
      expect(tester.getTopLeft(find.byType(ListView)).dy, 0);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
