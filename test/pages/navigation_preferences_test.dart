import 'dart:async';

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

// Exercise the real MainController with attached Flutter PageView/TabBarView
// controllers. Placeholder pages avoid starting unrelated network/player code.
class _NavigationHarness extends StatelessWidget {
  const _NavigationHarness();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: GetBuilder<MainController>(
      id: 'navigation',
      builder: (main) {
        final pages = main.navigationBars
            .map((bar) => Center(child: Text('page:${bar.name}')))
            .toList();
        return Scaffold(
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
