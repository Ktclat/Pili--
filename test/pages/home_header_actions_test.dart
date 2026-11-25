import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/models/common/bar_hide_type.dart';
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
    EdgeInsets contentInsets = EdgeInsets.zero,
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
        home: Scaffold(
          body: Padding(padding: contentInsets, child: const HomePage()),
        ),
        getPages: [
          GetPage(
            name: '/recognizeLink',
            page: () => const Scaffold(body: Text('识别页面')),
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
    return main;
  }

  testWidgets('guests see only enabled tools and can enable link recognition', (
    tester,
  ) async {
    await show(tester, const Size(360, 640));
    expect(find.byIcon(Icons.search_outlined), findsOneWidget);
    expect(find.byTooltip('扫一扫'), findsOneWidget);
    expect(find.byTooltip('点击登录'), findsOneWidget);
    expect(find.byTooltip('消息'), findsNothing);
    expect(find.byTooltip('识别链接'), findsNothing);
    expect(find.byTooltip('更多操作'), findsNothing);
    await HeaderActionPreferences.save(.home, [
      for (final entry in HeaderActionPage.home.defaults)
        (action: entry.action, pinned: true),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('识别链接'));
    await tester.pumpAndSettle();
    expect(find.text('识别页面'), findsOneWidget);
  });

  testWidgets(
    'custom order updates live in both side-bar and landscape layouts',
    (
      tester,
    ) async {
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
      expect(find.byTooltip('更多操作'), findsNothing);
    },
  );

  testWidgets(
    'turning off every tool leaves only the original search or tabs',
    (
      tester,
    ) async {
      await show(tester, const Size(360, 640));
      await HeaderActionPreferences.save(.home, [
        for (final entry in HeaderActionPage.home.defaults)
          (action: entry.action, pinned: false),
      ]);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.search_outlined), findsOneWidget);
      for (final label in ['扫一扫', '点击登录', '消息', '识别链接', '更多操作']) {
        expect(find.byTooltip(label), findsNothing);
      }
      tester.view.physicalSize = const Size(640, 360);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.search_outlined), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    },
  );

  testWidgets(
    'search contracts to an icon before any selected tool leaves the viewport',
    (
      tester,
    ) async {
      await show(tester, const Size(360, 640), loggedIn: true);
      await HeaderActionPreferences.save(.home, [
        for (final entry in HeaderActionPage.home.defaults)
          (action: entry.action, pinned: true),
      ]);
      await tester.pumpAndSettle();
      expect(find.byTooltip('搜索'), findsNothing);
      // Five 48 dp targets fit exactly after releasing the outer padding.
      tester.view.physicalSize = const Size(240, 640);
      await tester.pumpAndSettle();
      for (final label in ['搜索', '扫一扫', '消息', '我的', '识别链接']) {
        expect(find.byTooltip(label).hitTestable(), findsOneWidget);
      }
      expect(find.byTooltip('更多操作'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      expect(find.text('搜索页面'), findsOneWidget);
    },
  );

  testWidgets(
    'tools wrap into a directly tappable second row in an inset window',
    (
      tester,
    ) async {
      // A 360 dp window can give Home only 160 dp of usable width.
      await show(
        tester,
        const Size(360, 640),
        loggedIn: true,
        contentInsets: const EdgeInsets.symmetric(horizontal: 100),
      );
      await HeaderActionPreferences.save(.home, [
        for (final entry in HeaderActionPage.home.defaults)
          (action: entry.action, pinned: true),
      ]);
      await tester.pumpAndSettle();
      for (final label in ['搜索', '扫一扫', '消息', '我的', '识别链接']) {
        expect(find.byTooltip(label).hitTestable(), findsOneWidget);
      }
      final link = find.byTooltip('识别链接');
      expect(
        tester.getCenter(link).dy,
        greaterThan(tester.getCenter(find.byTooltip('搜索')).dy),
      );
      expect(find.byTooltip('更多操作'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.text('识别页面'), findsOneWidget);
    },
  );

  for (final type in BarHideType.values) {
    testWidgets(
      'the ${type.name} toolbar hides and reopens at either row count',
      (
        tester,
      ) async {
        settings.data
          ..[SettingBoxKey.hideTopBar] = true
          ..[SettingBoxKey.barHideType] = type.index;
        final main = await show(tester, const Size(360, 640), loggedIn: true);
        final home = Get.find<HomeController>();
        final scan = find.byTooltip('扫一扫');
        for (final width in [360.0, 150.0]) {
          tester.view.physicalSize = Size(width, 640);
          await tester.pumpAndSettle();
          expect(scan.hitTestable(), findsOneWidget);
          if (type == BarHideType.sync) {
            main.barOffset!.value = Style.topBarHeight;
          } else {
            home.showTopBar!.value = false;
          }
          await tester.pumpAndSettle();
          expect(scan.hitTestable(), findsNothing);
          if (type == BarHideType.sync) {
            main.barOffset!.value = 0;
          } else {
            home.showTopBar!.value = true;
          }
          await tester.pumpAndSettle();
          expect(scan.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'unread messages stay on the selected button and open the inbox',
    (
      tester,
    ) async {
      final main = await show(tester, const Size(220, 640), loggedIn: true);
      main.msgUnReadCount.value = '7';
      await tester.pumpAndSettle();
      final messages = find.byTooltip('消息');
      expect(
        find.descendant(of: messages, matching: find.text('7')),
        findsOneWidget,
      );
      expect(find.byTooltip('更多操作'), findsNothing);

      await HeaderActionPreferences.save(.home, [
        for (final entry in HeaderActionPage.home.defaults)
          (
            action: entry.action,
            pinned: entry.action != HeaderAction.messages && entry.pinned,
          ),
      ]);
      await tester.pumpAndSettle();
      expect(messages, findsNothing);
      expect(find.text('7'), findsNothing);
      await HeaderActionPreferences.save(.home, HeaderActionPage.home.defaults);
      await tester.pumpAndSettle();
      await tester.tap(messages);
      await tester.pumpAndSettle();
      expect(find.text('消息页面'), findsOneWidget);
      expect(main.msgUnReadCount.value, isNull);
      expect(main.lastCheckUnreadAt, greaterThan(0));
    },
  );
}
