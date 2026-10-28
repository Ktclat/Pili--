import 'dart:async';

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

  test(
    'existing enum indexes and default mall visibility remain compatible',
    () {
      expect(NavigationBarType.home.index, 0);
      expect(NavigationBarType.dynamics.index, 1);
      expect(NavigationBarType.mine.index, 2);
      expect(NavigationBarType.mall.index, 3);
      expect(Pref.showMallInNavigation, isTrue);
      expect(NavigationPreferences.bars, NavigationBarConfig.defaultOrder);
    },
  );

  test('legacy custom navigation adds mall without restoring hidden tabs', () {
    settings.data[SettingBoxKey.navBarSort] = [2, 0];
    expect(NavigationPreferences.bars, [
      NavigationBarType.mine,
      NavigationBarType.home,
      NavigationBarType.mall,
    ]);
    settings.data[SettingBoxKey.navBarSort] = [2];
    expect(NavigationPreferences.bars, [
      NavigationBarType.mine,
      NavigationBarType.mall,
    ]);
  });

  test(
    'navigation editor and visibility switch persist the same selection',
    () async {
      await NavigationPreferences.saveOrder([
        NavigationBarType.dynamics,
        NavigationBarType.mine,
      ]);
      expect(Pref.showMallInNavigation, isFalse);
      expect(NavigationPreferences.bars, [
        NavigationBarType.dynamics,
        NavigationBarType.mine,
      ]);

      await NavigationPreferences.setMallVisible(true);
      expect(Pref.showMallInNavigation, isTrue);
      expect(settings.data[SettingBoxKey.navBarSort], [1, 3, 2]);
      await NavigationPreferences.setMallVisible(false);
      expect(settings.data[SettingBoxKey.navBarSort], [1, 2]);
      expect(Pref.showMallInNavigation, isFalse);

      await NavigationPreferences.reset();
      expect(Pref.showMallInNavigation, isTrue);
      expect(NavigationPreferences.bars, NavigationBarConfig.defaultOrder);
    },
  );

  test(
    'malformed and mall-only saved preferences always leave a valid tab',
    () async {
      settings.data[SettingBoxKey.navBarSort] = [-1, 99, 'home', 2, 2];
      expect(NavigationPreferences.bars, [
        NavigationBarType.mine,
        NavigationBarType.mall,
      ]);
      settings.data[SettingBoxKey.defaultHomePage] = 99;
      expect(Pref.defaultHomePage, NavigationBarType.home);

      await NavigationPreferences.saveOrder([NavigationBarType.mall]);
      await NavigationPreferences.setMallVisible(false);
      expect(NavigationPreferences.bars, [NavigationBarType.home]);
      expect(() => NavigationPreferences.saveOrder([]), throwsArgumentError);
    },
  );

  for (final animated in [false, true]) {
    testWidgets(
      'hiding the current mall safely replaces the ${animated ? 'Tab' : 'Page'}Controller',
      (
        tester,
      ) async {
        settings.data[SettingBoxKey.mainTabBarView] = animated;
        settings.data[SettingBoxKey.defaultHomePage] =
            NavigationBarType.mall.index;
        final main = Get.put(MainController());
        await tester.pumpWidget(const _NavigationHarness());
        await tester.pumpAndSettle();
        expect(find.text('page:mall'), findsOneWidget);

        await NavigationPreferences.setMallVisible(false);
        main.reloadNavigation();
        await tester.pumpAndSettle();
        expect(main.navigationBars, [
          NavigationBarType.home,
          NavigationBarType.dynamics,
          NavigationBarType.mine,
        ]);
        expect(main.selectedIndex.value, 0);
        expect(find.text('page:home'), findsOneWidget);

        await NavigationPreferences.setMallVisible(true);
        main.reloadNavigation();
        // A tap arriving before the replacement view attaches must still select
        // the requested page after that frame, with no detached-controller error.
        main.setIndex(main.navigationBars.indexOf(NavigationBarType.mall));
        await tester.pumpAndSettle();
        expect(find.text('page:mall'), findsOneWidget);

        await NavigationPreferences.saveOrder([NavigationBarType.mall]);
        main.reloadNavigation();
        await tester.pumpAndSettle();
        expect(main.navigationBars, [NavigationBarType.mall]);
        expect(main.selectedIndex.value, 0);
        await NavigationPreferences.setMallVisible(false);
        main.reloadNavigation();
        await tester.pumpAndSettle();
        expect(main.navigationBars, [NavigationBarType.home]);
        expect(find.text('page:home'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'reordering preserves the selected tab and refreshes Mine index (${animated ? 'Tab' : 'Page'})',
      (
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
          NavigationBarType.mall,
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
      },
    );
  }
}
