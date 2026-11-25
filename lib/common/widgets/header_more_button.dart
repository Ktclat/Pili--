import 'package:PiliPlus/utils/header_action_preferences.dart';
import 'package:material_ui/material_ui.dart';

({List<HeaderAction> pinned, List<HeaderAction> more}) splitHeaderActions(
  List<HeaderActionEntry> entries,
  int slots,
) {
  final needsMenu = entries.length > slots || entries.any((e) => !e.pinned);
  final pinnedSlots = needsMenu ? slots - 1 : slots;
  final pinned = <HeaderAction>[];
  final more = <HeaderAction>[];
  for (final entry in entries) {
    if (entry.pinned && pinned.length < pinnedSlots) {
      pinned.add(entry.action);
    } else {
      more.add(entry.action);
    }
  }
  return (pinned: pinned, more: more);
}

class HeaderMoreButton extends StatelessWidget {
  const HeaderMoreButton({
    super.key,
    required this.items,
    this.icon = const Icon(Icons.more_vert),
  });

  final List<PopupMenuEntry<VoidCallback>> items;
  final Widget icon;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    tooltip: '更多操作',
    icon: icon,
    position: PopupMenuPosition.under,
    onSelected: (open) => open(),
    itemBuilder: (_) => items,
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
