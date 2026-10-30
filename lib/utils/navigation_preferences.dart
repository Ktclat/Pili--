import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';

/// Persist navigation order and visibility without restoring hidden tabs.
abstract final class NavigationPreferences {
  static List<NavigationBarType> get bars => NavigationBarConfig.resolve(
    GStorage.setting.get(SettingBoxKey.navBarSort),
  );

  static Future<void> saveOrder(List<NavigationBarType> order) {
    if (order.isEmpty) {
      throw ArgumentError.value(order, 'order', 'must not be empty');
    }
    return _save(
      NavigationBarConfig.resolve(
        order.map((bar) => bar.index).toList(),
      ),
    );
  }

  static Future<void> reset() => _save(
    NavigationBarConfig.defaultOrder,
  );

  static Future<void> _save(
    List<NavigationBarType> bars,
  ) => GStorage.setting.put(
    SettingBoxKey.navBarSort,
    bars.map((bar) => bar.index).toList(),
  );
}
