import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/setting/pages/header_actions.dart';
import 'package:PiliPlus/utils/header_action_preferences.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

const _customHome = <HeaderActionEntry>[
  (action: .recognizeLink, pinned: true),
  (action: .messages, pinned: false),
  (action: .scan, pinned: false),
  (action: .profile, pinned: true),
];

Future<T> _freshLaunch<T>(String path, Future<T> Function() run) =>
    Isolate.run(() async {
      GStorage.setting = await Hive.openBox<dynamic>('setting', path: path);
      try {
        return await run();
      } finally {
        await Hive.close();
      }
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pili-header-actions-');
    // Widget tests use Hive's in-memory backend so writes can complete on the
    // Flutter test clock. The restart test opens and closes an on-disk box.
    GStorage.setting = await Hive.openBox<dynamic>(
      'setting',
      bytes: Uint8List(0),
    );
  });
  setUp(() async {
    await GStorage.setting.clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('both pages show Scan and hide Recognize Link by default', () {
    List<HeaderAction> pinned(HeaderActionPage page, bool pinned) =>
        HeaderActionPreferences.read(page)
            .where((entry) => entry.pinned == pinned)
            .map((entry) => entry.action)
            .toList();
    expect(pinned(.home, true), [
      HeaderAction.scan,
      HeaderAction.messages,
      HeaderAction.profile,
    ]);
    expect(pinned(.home, false), [HeaderAction.recognizeLink]);
    expect(pinned(.mine, true), [
      HeaderAction.replyHistory,
      HeaderAction.incognito,
      HeaderAction.switchAccount,
      HeaderAction.theme,
      HeaderAction.settings,
      HeaderAction.scan,
    ]);
    expect(pinned(.mine, false), [
      HeaderAction.messages,
      HeaderAction.search,
      HeaderAction.recognizeLink,
    ]);
  });

  test(
    'upgrades keep explicit choices and apply the new Scan default',
    () async {
      await GStorage.setting.put(SettingBoxKey.mineHeaderActions, [
        {'id': 'recognizeLink', 'pinned': true},
        {'id': 'scan', 'pinned': false},
      ]);
      expect(HeaderActionPreferences.read(.mine).take(2), [
        (action: HeaderAction.recognizeLink, pinned: true),
        (action: HeaderAction.scan, pinned: false),
      ]);
      await GStorage.setting.put(SettingBoxKey.mineHeaderActions, [
        {'id': 'scan', 'pinned': null},
      ]);
      expect(HeaderActionPreferences.read(.mine).first, (
        action: HeaderAction.scan,
        pinned: true,
      ));
    },
  );

  test('Mine defaults follow navigation until explicitly customized', () async {
    final homeVisible = HeaderActionPreferences.read(.mine);
    await GStorage.setting.put(SettingBoxKey.navBarSort, [
      NavigationBarType.mine.index,
    ]);
    final homeHidden = HeaderActionPreferences.read(.mine);
    expect(homeHidden, [
      for (final entry in homeVisible)
        if (entry.action == HeaderAction.messages ||
            entry.action == HeaderAction.search)
          (action: entry.action, pinned: true)
        else
          entry,
    ]);
    final edited = [
      for (final entry in homeHidden.reversed)
        if (entry.action == HeaderAction.search)
          (action: entry.action, pinned: false)
        else
          entry,
    ];
    await HeaderActionPreferences.save(.mine, edited);
    await GStorage.setting.delete(SettingBoxKey.navBarSort);
    expect(HeaderActionPreferences.read(.mine), [
      for (final entry in edited)
        if (entry.action == HeaderAction.messages)
          (action: entry.action, pinned: false)
        else
          entry,
    ]);
    await GStorage.setting.put(SettingBoxKey.navBarSort, [
      NavigationBarType.mine.index,
    ]);
    expect(HeaderActionPreferences.read(.mine), edited);
    await HeaderActionPreferences.reset(.mine);
    expect(HeaderActionPreferences.read(.mine), homeHidden);
  });

  test(
    'corrupt entries are skipped and missing actions follow saved ones',
    () async {
      final defaults = HeaderActionPreferences.read(.home);
      await GStorage.setting.put(SettingBoxKey.homeHeaderActions, 'damaged');
      expect(HeaderActionPreferences.read(.home), defaults);
      await GStorage.setting.put(SettingBoxKey.homeHeaderActions, [
        {'id': 'retired', 'pinned': true},
        {'id': 'incognito', 'pinned': true}, // Available on Mine only.
        42,
        {'id': 'messages', 'pinned': 'damaged'},
        {'id': 'recognizeLink', 'pinned': true},
        {'id': 'recognizeLink', 'pinned': false},
        {'id': 'scan', 'pinned': false},
      ]);
      expect(HeaderActionPreferences.read(.home), [
        (action: HeaderAction.recognizeLink, pinned: true),
        (action: HeaderAction.scan, pinned: false),
        ...defaults.where(
          (entry) =>
              entry.action == HeaderAction.messages ||
              entry.action == HeaderAction.profile,
        ),
      ]);
    },
  );

  test(
    'both pages retain their own order and visibility across launches',
    () async {
      final db = await directory.createTemp('restart-');
      await _freshLaunch(db.path, () async {
        await HeaderActionPreferences.save(.home, _customHome);
        final mine = HeaderActionPreferences.read(.mine).reversed
            .map((entry) => (action: entry.action, pinned: false))
            .toList();
        await HeaderActionPreferences.save(.mine, mine);
      });
      final restored = await _freshLaunch(db.path, () async {
        final home = HeaderActionPreferences.read(.home);
        final mine = HeaderActionPreferences.read(.mine);
        await HeaderActionPreferences.reset(.home);
        return (home, mine, HeaderActionPreferences.read(.mine));
      });
      expect(restored.$1, _customHome);
      expect(restored.$2, [
        for (final entry in HeaderActionPreferences.read(.mine).reversed)
          (action: entry.action, pinned: false),
      ]);
      expect(restored.$3, restored.$2);
    },
  );

  testWidgets('toggling, switching pages and restoring defaults auto-apply', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: HeaderActionSettingsPage()),
    );
    await tester.pumpAndSettle();
    Finder row(String label) => find.widgetWithText(CheckboxListTile, label);
    bool checked(String label) =>
        tester.widget<CheckboxListTile>(row(label)).value!;
    final home = HeaderActionPreferences.read(.home);
    final mine = HeaderActionPreferences.read(.mine);
    expect(checked('识别链接'), isFalse);
    await tester.tap(row('识别链接'));
    await tester.pumpAndSettle();
    expect(checked('识别链接'), isTrue);
    expect(HeaderActionPreferences.read(.home), [
      for (final entry in home)
        (
          action: entry.action,
          pinned: entry.pinned || entry.action == HeaderAction.recognizeLink,
        ),
    ]);
    final handle = find.byTooltip('拖动调整识别链接的位置');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byTooltip('拖动调整扫一扫的位置')));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(HeaderActionPreferences.read(.home).first, (
      action: HeaderAction.recognizeLink,
      pinned: true,
    ));
    await tester.tap(find.widgetWithText(Tab, '我的'));
    await tester.pumpAndSettle();
    expect(checked('搜索'), isFalse);
    await tester.tap(row('搜索'));
    await tester.pumpAndSettle();
    expect(checked('搜索'), isTrue);
    final changedMine = HeaderActionPreferences.read(.mine);
    expect(changedMine, isNot(mine));
    await tester.tap(find.widgetWithText(Tab, '首页'));
    await tester.pumpAndSettle();
    expect(checked('识别链接'), isTrue);
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(checked('识别链接'), isFalse);
    expect(HeaderActionPreferences.read(.home), home);
    expect(HeaderActionPreferences.read(.mine), changedMine);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
