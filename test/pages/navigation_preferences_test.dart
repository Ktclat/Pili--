import 'dart:async';

import 'package:PiliPlus/common/widgets/floating_navigation_bar.dart';
import 'package:PiliPlus/models/common/bar_hide_type.dart';
import 'package:PiliPlus/models/common/member/tab_type.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/navigation_preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Settings extends Fake implements Box<dynamic> {
  final data = <dynamic, dynamic>{};
  final events = StreamController<BoxEvent>.broadcast(sync: true);

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) => putAll({key: value});

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    data.addAll(entries);
    for (final entry in entries.entries) {
      events.add(BoxEvent(entry.key, entry.value, false));
    }
  }

  @override
  Stream<BoxEvent> watch({dynamic key}) =>
      events.stream.where((event) => key == null || event.key == key);
}

class _GuestAccountService extends GetxService implements AccountService {
  @override
  final RxString face = ''.obs;
  @override
  final RxBool isLogin = false.obs;
}

class _RecordingMainController extends MainController {
  final selections = <int>[];

  @override
  void setIndex(int value) {
    selections.add(value);
    super.setIndex(value);
  }
}

// Exercise the real MainController with attached Flutter PageView/TabBarView
// controllers. Placeholder pages avoid starting unrelated network/player code.
class _NavigationHarness extends StatelessWidget {
  const _NavigationHarness({this.showNavigation = false});

  final bool showNavigation;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: GetBuilder<MainController>(
      id: 'navigation',
      builder: (main) {
        final revision = main.navigationRevision;
        final pages = main.navigationBars
            .map((bar) => Center(child: Text('page:${bar.name}')))
            .toList();
        return Scaffold(
          bottomNavigationBar: showNavigation
              ? Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 1,
                  child: Obx(
                    () => main.floatingNavBar
                        ? FloatingNavigationBar(
                            key: ValueKey(revision),
                            interactionEnabled: main.bottomBarFullyVisible,
                            selectedIndex: main.selectedIndex.value,
                            onDestinationSelected: (index) =>
                                main.setFloatingDestination(
                                  index,
                                  revision: revision,
                                ),
                            destinations: main.navigationBars
                                .map(
                                  (bar) => FloatingNavigationDestination(
                                    label: bar.label,
                                    icon: bar.icon,
                                    selectedIcon: bar.selectIcon,
                                  ),
                                )
                                .toList(),
                          )
                        : NavigationBar(
                            selectedIndex: main.selectedIndex.value,
                            onDestinationSelected: main.setIndex,
                            destinations: main.navigationBars
                                .map(
                                  (bar) => NavigationDestination(
                                    icon: bar.icon,
                                    label: bar.label,
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                )
              : null,
          body: main.mainTabBarView
              ? TabBarView(
                  key: ValueKey(main.navigationRevision),
                  controller: main.controller,
                  children: pages,
                )
              : PageView(
                  key: ValueKey(main.navigationRevision),
                  controller: main.controller,
                  children: pages,
                ),
        );
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = _Settings();
  setUpAll(() => GStorage.setting = settings);
  tearDownAll(settings.events.close);

  setUp(() {
    Get.testMode = true;
    settings.data
      ..clear()
      ..addAll({
        SettingBoxKey.autoUpdate: false,
        SettingBoxKey.dynamicBadgeMode: 0,
        SettingBoxKey.msgBadgeMode: 0,
        SettingBoxKey.feedBackEnable: false,
      });
    Get.put<AccountService>(_GuestAccountService());
  });
  tearDown(Get.reset);

  test('existing navigation indexes stay stable after the upgrade', () {
    expect(NavigationBarType.home.index, 0);
    expect(NavigationBarType.dynamics.index, 1);
    expect(NavigationBarType.mine.index, 2);
    expect(NavigationPreferences.bars, NavigationBarConfig.defaultOrder);
  });

  test(
    'floating navigation defaults on while preserving an explicit opt-out',
    () {
      expect(Pref.floatingNavBar, isTrue);
      settings.data[SettingBoxKey.floatingNavBar] = false;
      expect(Pref.floatingNavBar, isFalse);
      final main = Get.put(MainController());
      expect(main.floatingNavBar, isFalse);
    },
  );

  test('retired indexes are dropped without restoring hidden tabs', () {
    settings.data[SettingBoxKey.navBarSort] = [2, 3, 0, 2, 99];
    expect(NavigationPreferences.bars, [
      NavigationBarType.mine,
      NavigationBarType.home,
    ]);
    settings.data[SettingBoxKey.navBarSort] = [3, 2];
    expect(NavigationPreferences.bars, [NavigationBarType.mine]);
  });

  test('navigation editor persists selection and can reset defaults', () async {
    await NavigationPreferences.saveOrder([
      NavigationBarType.dynamics,
      NavigationBarType.mine,
    ]);
    expect(settings.data[SettingBoxKey.navBarSort], [1, 2]);
    expect(NavigationPreferences.bars, [
      NavigationBarType.dynamics,
      NavigationBarType.mine,
    ]);
    await NavigationPreferences.reset();
    expect(NavigationPreferences.bars, NavigationBarConfig.defaultOrder);
    expect(() => NavigationPreferences.saveOrder([]), throwsArgumentError);
  });

  test('malformed and retired startup preferences have valid fallbacks', () {
    settings.data[SettingBoxKey.navBarSort] = [-1, 99, 'home', 2, 2];
    expect(NavigationPreferences.bars, [NavigationBarType.mine]);
    for (final value in [
      null,
      [],
      [3],
      [-1, 99, 'home'],
      'invalid',
    ]) {
      settings.data[SettingBoxKey.navBarSort] = value;
      expect(NavigationPreferences.bars, NavigationBarConfig.defaultOrder);
    }
    for (final value in [3, -1, 99, 'home']) {
      settings.data[SettingBoxKey.defaultHomePage] = value;
      expect(Pref.defaultHomePage, NavigationBarType.home);
    }
    settings.data[SettingBoxKey.defaultHomePage] = 2;
    expect(Pref.defaultHomePage, NavigationBarType.mine);

    // The removed profile tab occupied index 7; earlier choices keep their IDs.
    settings.data[SettingBoxKey.memberTab] = 7;
    expect(Pref.memberTab, MemberTabType.def);
    settings.data[SettingBoxKey.memberTab] = 6;
    expect(Pref.memberTab, MemberTabType.cheese);
    expect(MemberTabType.contains('shop'), isFalse);
  });

  for (final animated in [false, true]) {
    final controllerType = animated ? 'Tab' : 'Page';

    testWidgets(
      'changing navigation style preserves the active $controllerType',
      (
        tester,
      ) async {
        settings.data[SettingBoxKey.mainTabBarView] = animated;
        settings.data[SettingBoxKey.defaultHomePage] =
            NavigationBarType.mine.index;
        final main = Get.put(MainController());
        await tester.pumpWidget(const _NavigationHarness(showNavigation: true));
        await tester.pumpAndSettle();
        final pageController = main.controller;
        expect(find.byType(FloatingNavigationBar), findsOneWidget);
        expect(find.text('page:mine'), findsOneWidget);

        main.setFloatingNavBar(false);
        await tester.pumpAndSettle();
        expect(find.byType(FloatingNavigationBar), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(main.controller, same(pageController));
        expect(main.selectedIndex.value, NavigationBarType.mine.index);
        expect(find.text('page:mine'), findsOneWidget);

        main.setFloatingNavBar(true);
        await tester.pumpAndSettle();
        expect(find.byType(FloatingNavigationBar), findsOneWidget);
        expect(main.controller, same(pageController));
        expect(main.navigationRevision, 0);
        expect(find.text('page:mine'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('drag dwell switches the real $controllerType only once', (
      tester,
    ) async {
      settings.data[SettingBoxKey.mainTabBarView] = animated;
      final main = _RecordingMainController();
      Get.put<MainController>(main);
      await tester.pumpWidget(const _NavigationHarness(showNavigation: true));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('首页')),
      );
      await gesture.moveTo(tester.getCenter(find.text('我的')));
      await tester.pump(const Duration(milliseconds: 199));
      expect(main.selectedIndex.value, NavigationBarType.home.index);
      expect(main.selections, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(main.selectedIndex.value, NavigationBarType.mine.index);
      await tester.pumpAndSettle();
      expect(find.text('page:mine'), findsOneWidget);
      expect(main.selections, [NavigationBarType.mine.index]);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(main.selections, [NavigationBarType.mine.index]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'navigation reordering cancels a pending drag with $controllerType',
      (
        tester,
      ) async {
        settings.data[SettingBoxKey.mainTabBarView] = animated;
        final main = _RecordingMainController();
        Get.put<MainController>(main);
        await tester.pumpWidget(const _NavigationHarness(showNavigation: true));
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('首页')),
        );
        await gesture.moveTo(tester.getCenter(find.text('我的')));
        await tester.pump(const Duration(milliseconds: 100));
        await NavigationPreferences.saveOrder([
          NavigationBarType.home,
          NavigationBarType.mine,
          NavigationBarType.dynamics,
        ]);
        main.reloadNavigation();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        expect(main.selectedIndex.value, NavigationBarType.home.index);
        expect(main.selections, isEmpty);
        expect(find.text('page:home'), findsOneWidget);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(main.selections, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    for (final hideType in BarHideType.values) {
      testWidgets(
        '${hideType.name} hiding cancels pending $controllerType navigation',
        (tester) async {
          settings.data[SettingBoxKey.mainTabBarView] = animated;
          settings.data[SettingBoxKey.hideBottomBar] = true;
          settings.data[SettingBoxKey.barHideType] = hideType.index;
          final main = _RecordingMainController();
          Get.put<MainController>(main);
          await tester.pumpWidget(
            const _NavigationHarness(showNavigation: true),
          );
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('首页')),
          );
          await gesture.moveTo(tester.getCenter(find.text('我的')));
          await tester.pump(const Duration(milliseconds: 100));
          if (hideType == BarHideType.instant) {
            main.showBottomBar!.value = false;
          } else {
            main.barOffset!.value = 1;
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(main.bottomBarFullyVisible, isFalse);
          expect(main.selectedIndex.value, NavigationBarType.home.index);
          expect(main.selections, isEmpty);
          await gesture.up();
          if (hideType == BarHideType.instant) {
            main.showBottomBar!.value = true;
          } else {
            main.barOffset!.value = 0;
          }
          await tester.pumpAndSettle();
          expect(main.bottomBarFullyVisible, isTrue);
          expect(main.selections, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets('retired-only preferences can start with $controllerType', (
      tester,
    ) async {
      settings.data[SettingBoxKey.mainTabBarView] = animated;
      settings.data[SettingBoxKey.navBarSort] = [3];
      settings.data[SettingBoxKey.defaultHomePage] = 3;
      final main = Get.put(MainController());
      await tester.pumpWidget(const _NavigationHarness());
      await tester.pumpAndSettle();
      expect(main.navigationBars, NavigationBarConfig.defaultOrder);
      expect(main.selectedIndex.value, 0);
      expect(find.text('page:home'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('removing the selected tab safely replaces $controllerType', (
      tester,
    ) async {
      settings.data[SettingBoxKey.mainTabBarView] = animated;
      settings.data[SettingBoxKey.defaultHomePage] =
          NavigationBarType.dynamics.index;
      final main = Get.put(MainController());
      await tester.pumpWidget(const _NavigationHarness());
      await tester.pumpAndSettle();
      expect(find.text('page:dynamics'), findsOneWidget);

      await NavigationPreferences.saveOrder([
        NavigationBarType.home,
        NavigationBarType.mine,
      ]);
      main.reloadNavigation();
      await tester.pumpAndSettle();
      expect(main.selectedIndex.value, 0);
      expect(find.text('page:home'), findsOneWidget);

      await NavigationPreferences.reset();
      main.reloadNavigation();
      // A tap before the replacement view attaches must select the requested
      // tab after that frame without a detached-controller exception.
      main.setIndex(main.navigationBars.indexOf(NavigationBarType.dynamics));
      await tester.pumpAndSettle();
      expect(find.text('page:dynamics'), findsOneWidget);

      await NavigationPreferences.saveOrder([NavigationBarType.dynamics]);
      main.reloadNavigation();
      await tester.pumpAndSettle();
      expect(main.selectedIndex.value, 0);
      await NavigationPreferences.saveOrder([NavigationBarType.home]);
      main.reloadNavigation();
      await tester.pumpAndSettle();
      expect(find.text('page:home'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('reordering keeps Mine selected with $controllerType', (
      tester,
    ) async {
      settings.data[SettingBoxKey.mainTabBarView] = animated;
      settings.data[SettingBoxKey.defaultHomePage] =
          NavigationBarType.mine.index;
      final main = Get.put(MainController());
      await tester.pumpWidget(const _NavigationHarness());
      await tester.pumpAndSettle();
      main.toMinePage();

      await NavigationPreferences.saveOrder([
        NavigationBarType.mine,
        NavigationBarType.dynamics,
      ]);
      main.reloadNavigation();
      await tester.pumpAndSettle();
      expect(main.selectedIndex.value, 0);
      expect(find.text('page:mine'), findsOneWidget);
      main.setIndex(1);
      await tester.pumpAndSettle();
      main.toMinePage();
      await tester.pumpAndSettle();
      expect(main.selectedIndex.value, 0);
      expect(find.text('page:mine'), findsOneWidget);
      main.setIndex(99);
      expect(main.selectedIndex.value, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
