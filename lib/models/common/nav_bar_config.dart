import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/pages/dynamics/view.dart';
import 'package:PiliPlus/pages/home/view.dart';
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
    NavigationBarType.mine,
  ];

  /// Keep valid saved tabs in order, ignoring retired or malformed indexes.
  static List<NavigationBarType> resolve(Object? savedOrder) {
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
