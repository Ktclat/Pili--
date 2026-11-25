import 'package:PiliPlus/pages/setting/pages/header_actions.dart';
import 'package:PiliPlus/utils/header_action_preferences.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps editing reachable even when every action has been moved into the menu.
class HeaderMoreButton extends StatelessWidget {
  const HeaderMoreButton({
    super.key,
    required this.page,
    required this.items,
    this.icon = const Icon(Icons.more_vert),
  });

  final HeaderActionPage page;
  final List<PopupMenuEntry<VoidCallback>> items;
  final Widget icon;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    tooltip: '更多操作',
    icon: icon,
    position: PopupMenuPosition.under,
    onSelected: (open) => open(),
    itemBuilder: (_) => [
      ...items,
      if (items.isNotEmpty) const PopupMenuDivider(),
      headerMenuItem(
        label: '编辑按钮',
        icon: const Icon(Icons.edit_outlined),
        onPressed: () =>
            Get.to(() => HeaderActionSettingsPage(initialPage: page)),
      ),
    ],
  );
}

PopupMenuItem<VoidCallback> headerMenuItem({
  required String label,
  required Widget icon,
  required VoidCallback onPressed,
}) => PopupMenuItem(
  value: onPressed,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 12,
    children: [
      icon,
      Flexible(child: Text(label)),
    ],
  ),
);
