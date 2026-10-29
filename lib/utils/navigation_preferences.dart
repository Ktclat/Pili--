import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';

/// One persisted source for the navigation editor and the mall visibility switch.
abstract final class NavigationPreferences {
  static bool get showMall =>
      GStorage.setting.get(SettingBoxKey.showMallInNavigation) != false;

  static List<NavigationBarType> get bars => NavigationBarConfig.resolve(
    GStorage.setting.get(SettingBoxKey.navBarSort),
    showMall: showMall,
  );

  static Future<void> setMallVisible(bool visible) => _save(
    NavigationBarConfig.resolve(
      GStorage.setting.get(SettingBoxKey.navBarSort),
      showMall: visible,
    ),
    showMall: visible,
  );

  static Future<void> saveOrder(List<NavigationBarType> order) {
    if (order.isEmpty) {
      throw ArgumentError.value(order, 'order', 'must not be empty');
    }
    final showMall = order.contains(NavigationBarType.mall);
    return _save(
      NavigationBarConfig.resolve(
        order.map((bar) => bar.index).toList(),
        showMall: showMall,
      ),
      showMall: showMall,
    );
  }

  static Future<void> reset() => _save(
    NavigationBarConfig.defaultOrder,
    showMall: true,
  );

  static Future<void> _save(
    List<NavigationBarType> bars, {
    required bool showMall,
  }) => GStorage.setting.putAll({
    SettingBoxKey.navBarSort: bars.map((bar) => bar.index).toList(),
    SettingBoxKey.showMallInNavigation: showMall,
  });
}
