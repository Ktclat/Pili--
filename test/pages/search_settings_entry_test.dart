import 'dart:typed_data';

import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/search/view.dart';
import 'package:PiliPlus/pages/setting/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/header_action_preferences.dart';
import 'package:PiliPlus/utils/navigation_preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GStorage.setting = await Hive.openBox('setting', bytes: Uint8List(0));
    GStorage.historyWord = await Hive.openBox('history', bytes: Uint8List(0));
    Accounts.account = await Hive.openBox<LoginAccount>(
      'account',
      bytes: Uint8List(0),
    );
  });
  setUp(() async {
    Get.testMode = true;
    await GStorage.setting.clear();
    await GStorage.setting.putAll({
      SettingBoxKey.enableHotKey: false,
      SettingBoxKey.enableSearchRcmd: false,
      SettingBoxKey.searchSuggestion: false,
    });
  });
  tearDown(Get.reset);
  tearDownAll(Hive.close);

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        home: const SearchPage(),
        getPages: [GetPage(name: '/setting', page: () => const SettingPage())],
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> hideProfile() => HeaderActionPreferences.save(.home, [
    for (final entry in HeaderActionPage.home.defaults)
      (action: entry.action, pinned: entry.pinned && entry.action != .profile),
  ]);

  testWidgets(
    'Search can restore settings when both Profile paths are hidden',
    (
      tester,
    ) async {
      await NavigationPreferences.saveOrder([NavigationBarType.home]);
      await hideProfile();
      await show(tester);

      final settings = find.widgetWithText(ListTile, '设置');
      expect(settings.hitTestable(), findsOneWidget);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(find.byType(SettingPage), findsOneWidget);

      await HeaderActionPreferences.reset(.home);
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(find.byType(SearchPage), findsOneWidget);
      expect(settings, findsNothing);
    },
  );

  testWidgets('Search leaves settings in Mine when its tab is available', (
    tester,
  ) async {
    await hideProfile();
    await show(tester);
    expect(find.widgetWithText(ListTile, '设置'), findsNothing);
  });
}
