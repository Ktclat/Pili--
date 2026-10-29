import 'dart:io';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('upgrade removes retired files and preserves unrelated user data', () async {
    final directory = await Directory.systemTemp.createTemp('pili-upgrade-');
    Hive.init(directory.path);
    try {
      final settings = await Hive.openBox<dynamic>('setting');
      GStorage.setting = settings;
      final retired = await Hive.openBox<dynamic>('mall');
      await retired.put('favorites', [123]);
      await retired.close();
      final cache = await Hive.openBox<dynamic>('localCache');
      await cache.put('download', {'id': 'keep'});
      await settings.putAll({
        'showMallInNavigation': true,
        'showMemberShop': true,
        SettingBoxKey.navBarSort: [2, 3, 0],
        SettingBoxKey.autoUpdate: false,
      });

      await GStorage.cleanupRetiredData();
      await GStorage.cleanupRetiredData(); // Also safe on subsequent launches.

      expect(await Hive.boxExists('mall'), isFalse);
      expect(settings.containsKey('showMallInNavigation'), isFalse);
      expect(settings.containsKey('showMemberShop'), isFalse);
      expect(settings.get(SettingBoxKey.navBarSort), [2, 3, 0]);
      expect(settings.get(SettingBoxKey.autoUpdate), isFalse);
      expect(cache.get('download'), {'id': 'keep'});
      await Hive.close();
      final restored = await Hive.openBox<dynamic>('setting');
      expect(restored.get(SettingBoxKey.navBarSort), [2, 3, 0]);
      expect(restored.containsKey('showMallInNavigation'), isFalse);
      expect((await Hive.openBox<dynamic>('localCache')).get('download'), {
        'id': 'keep',
      });
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
