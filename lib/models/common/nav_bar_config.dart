import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/pages/dynamics/view.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/mall/view.dart';
import 'package:PiliPlus/pages/mine/view.dart';
import 'package:material_ui/material_ui.dart';

enum NavigationBarType implements EnumWithLabel {
  home(
    '首页',
    Icon(Icons.home_outlined),
    Icon(Icons.home),
    HomePage(),
  ),
  dynamics(
    '动态',
    Icon(CustomIcons.motion_photos_on_outlined),
    Icon(CustomIcons.motion_photos_on),
    DynamicsPage(),
  ),
  mine(
    '我的',
    Icon(Icons.person_outline),
    Icon(Icons.person),
    MinePage(),
  ),
  // Keep existing indexes stable for saved navigation and startup preferences.
  mall(
    '会员购',
    Icon(Icons.shopping_bag_outlined),
    Icon(Icons.shopping_bag),
    MallPage(embeddedInNavigation: true),
  ),
  ;

  @override
  final String label;
  final Icon icon;
  final Icon selectIcon;
  final Widget page;

  const NavigationBarType(this.label, this.icon, this.selectIcon, this.page);
}

abstract final class NavigationBarConfig {
  static const defaultOrder = [
    NavigationBarType.home,
    NavigationBarType.dynamics,
    NavigationBarType.mall,
    NavigationBarType.mine,
  ];

  /// Accept old saved indexes without restoring tabs the user already hid.
  static List<NavigationBarType> resolve(
    Object? savedOrder, {
    required bool showMall,
  }) {
    final bars = <NavigationBarType>[];
    if (savedOrder is List) {
      for (final index in savedOrder) {
        if (index is int &&
            index >= 0 &&
            index < NavigationBarType.values.length) {
          final bar = NavigationBarType.values[index];
          if (!bars.contains(bar)) bars.add(bar);
        }
      }
    }
    if (bars.isEmpty) bars.addAll(defaultOrder);
    if (showMall && !bars.contains(NavigationBarType.mall)) {
      final mineIndex = bars.indexOf(NavigationBarType.mine);
      // Do not change the fallback startup tab for a custom order beginning
      // with Mine. The order of every existing tab stays unchanged.
      bars.insert(
        mineIndex > 0 ? mineIndex : bars.length,
        NavigationBarType.mall,
      );
    } else if (!showMall) {
      bars.remove(NavigationBarType.mall);
    }
    if (bars.isEmpty) bars.add(NavigationBarType.home);
    return bars;
  }

  static int selectedIndex(
    List<NavigationBarType> bars,
    NavigationBarType preferred,
  ) {
    final index = bars.indexOf(preferred);
    return index < 0 ? 0 : index;
  }
}
