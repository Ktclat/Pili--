import 'package:PiliPlus/utils/header_action_preferences.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class HeaderActionSettingsPage extends StatelessWidget {
  const HeaderActionSettingsPage({
    super.key,
    this.initialPage = HeaderActionPage.home,
  });

  final HeaderActionPage initialPage;

  Future<void> _persist(BuildContext context, Future<void> write) async {
    try {
      await write;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法保存右上角按钮设置，请重试')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    initialIndex: initialPage.index,
    length: HeaderActionPage.values.length,
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('右上角按钮'),
          actions: [
            TextButton(
              onPressed: () {
                final page =
                    HeaderActionPage.values[DefaultTabController.of(context)
                        .index];
                _persist(context, HeaderActionPreferences.reset(page));
              },
              child: const Text('恢复默认'),
            ),
          ],
          bottom: TabBar(
            tabs: [
              for (final page in HeaderActionPage.values) Tab(text: page.label),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: TabBarView(
            children: [
              for (final page in HeaderActionPage.values)
                _actionList(context, page),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _actionList(BuildContext context, HeaderActionPage page) => Obx(() {
    final entries = HeaderActionPreferences.read(page);
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      header: const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('勾选的按钮显示在右上角，收起的按钮放入「更多操作」。拖动右侧手柄调整顺序。'),
      ),
      itemCount: entries.length,
      onReorderItem: (oldIndex, newIndex) {
        final order = HeaderActionPreferences.read(page);
        order.insert(newIndex, order.removeAt(oldIndex));
        _persist(context, HeaderActionPreferences.save(page, order));
      },
      itemBuilder: (context, index) {
        final entry = entries[index];
        final label = entry.action == HeaderAction.profile
            ? '我的头像'
            : entry.action.label;
        return Row(
          key: ValueKey(entry.action),
          children: [
            Expanded(
              child: CheckboxListTile(
                title: Text(label),
                subtitle: switch (entry.action) {
                  HeaderAction.messages => const Text('登录后可用'),
                  HeaderAction.replyHistory => const Text('开启「记录评论」后可用'),
                  _ => null,
                },
                controlAffinity: ListTileControlAffinity.leading,
                value: entry.pinned,
                onChanged: (value) {
                  if (value == null) return;
                  final order = HeaderActionPreferences.read(page);
                  final position = order.indexWhere(
                    (item) => item.action == entry.action,
                  );
                  order[position] = (action: entry.action, pinned: value);
                  _persist(context, HeaderActionPreferences.save(page, order));
                },
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: '拖动调整$label的位置',
                child: const SizedBox.square(
                  dimension: kMinInteractiveDimension,
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ),
          ],
        );
      },
    );
  });
}
