import 'package:PiliPlus/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/header_action_preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Settings extends Fake implements Box<dynamic> {
  final data = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    data[key] = value;
  }
}

class _Account extends GetxService implements AccountService {
  @override
  final RxString face = ''.obs;
  @override
  final RxBool isLogin = false.obs;
}

// Keep the actual home layouts and routes but avoid constructing feed pages.
class _Home extends HomeController {
  @override
  void setTabConfig() {
    tabs = [];
    tabController = TabController(length: 0, vsync: this);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = _Settings();
  setUpAll(() => GStorage.setting = settings);
  setUp(() {
    Get.testMode = true;
    MineController.anonymity = false.obs;
    settings.data
      ..clear()
      ..addAll({
        SettingBoxKey.autoUpdate: false,
        SettingBoxKey.dynamicBadgeMode: 0,
        SettingBoxKey.msgBadgeMode: 0,
        SettingBoxKey.feedBackEnable: false,
      });
  });
  tearDown(Get.reset);

  Future<MainController> show(
    WidgetTester tester,
    Size size, {
    bool loggedIn = false,
    bool sideBar = false,
  }) async {
    settings.data[SettingBoxKey.useSideBar] = sideBar;
    final account = Get.put<AccountService>(_Account());
    account.isLogin.value = loggedIn;
    final main = Get.put(MainController())
      ..msgBadgeMode = DynamicBadgeMode.number;
    Get.put<HomeController>(_Home());
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: HomePage()),
        getPages: [
          GetPage(
            name: '/recognizeLink',
            page: () => const Scaffold(body: Text('识别页面')),
          ),
          GetPage(
            name: '/whisper',
            page: () => const Scaffold(body: Text('消息页面')),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return main;
  }

  testWidgets(
    'portrait defaults keep search, scan and guest avatar reachable',
    (tester) async {
      await show(tester, const Size(360, 640));
      expect(find.byIcon(Icons.search_outlined), findsOneWidget);
      expect(find.byTooltip('扫一扫'), findsOneWidget);
      expect(find.byTooltip('点击登录'), findsOneWidget);
      expect(find.byTooltip('消息'), findsNothing);
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      expect(find.text('消息'), findsNothing);
      expect(find.text('编辑按钮'), findsOneWidget);
      await tester.tap(find.text('识别链接'));
      await tester.pumpAndSettle();
      expect(find.text('识别页面'), findsOneWidget);
    },
  );

  testWidgets(
    'custom order updates live in both side-bar and landscape layouts',
    (tester) async {
      await show(tester, const Size(360, 640), sideBar: true);
      expect(find.byIcon(Icons.search_outlined), findsNothing);
      await HeaderActionPreferences.save(.home, [
        (action: .recognizeLink, pinned: true),
        (action: .scan, pinned: true),
        (action: .messages, pinned: false),
        (action: .profile, pinned: false),
      ]);
      await tester.pumpAndSettle();
      final link = find.byTooltip('识别链接');
      final scan = find.byTooltip('扫一扫');
      expect(tester.getCenter(link).dx, lessThan(tester.getCenter(scan).dx));
      expect(find.byTooltip('点击登录'), findsNothing);
      tester.view.physicalSize = const Size(800, 400);
      await tester.pumpAndSettle();
      expect(tester.getCenter(link).dx, lessThan(tester.getCenter(scan).dx));
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      expect(find.text('我的'), findsOneWidget);
      expect(find.text('编辑按钮'), findsOneWidget);
    },
  );

  testWidgets('rotating a phone keeps an all-collapsed toolbar editable', (
    tester,
  ) async {
    await show(tester, const Size(360, 640));
    await HeaderActionPreferences.save(.home, [
      for (final entry in HeaderActionPage.home.defaults)
        (action: entry.action, pinned: false),
    ]);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.search_outlined), findsOneWidget);
    expect(find.byTooltip('扫一扫'), findsNothing);
    tester.view.physicalSize = const Size(640, 360);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.search_outlined), findsNothing);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('扫一扫'), findsOneWidget);
    expect(find.text('识别链接'), findsOneWidget);
    expect(find.text('编辑按钮'), findsOneWidget);
  });

  testWidgets(
    'narrow header keeps unread messages in More and opens the inbox',
    (tester) async {
      final main = await show(tester, const Size(220, 640), loggedIn: true);
      main.msgUnReadCount.value = '7';
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('扫一扫'), findsOneWidget);
      expect(find.byTooltip('消息'), findsNothing);
      expect(
        find.descendant(of: find.byTooltip('更多操作'), matching: find.text('7')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      expect(find.text('消息'), findsOneWidget);
      await tester.tap(find.text('消息'));
      await tester.pumpAndSettle();
      expect(find.text('消息页面'), findsOneWidget);
      expect(main.msgUnReadCount.value, isNull);
      expect(main.lastCheckUnreadAt, greaterThan(0));
    },
  );
}
