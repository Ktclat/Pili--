import 'package:PiliPlus/models/mall/mall.dart';
import 'package:PiliPlus/pages/mall/widgets.dart';
import 'package:PiliPlus/utils/mall_local_store.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

class MallLibraryPage extends StatelessWidget {
  const MallLibraryPage({
    super.key,
    required this.store,
    required this.onOpen,
    this.showHistory = false,
  });

  final MallLocalStore store;
  final ValueChanged<MallProduct> onOpen;
  final bool showHistory;

  Future<void> _save(BuildContext context, Future<void> action) async {
    try {
      await action;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能保存本机记录，请稍后重试')),
        );
      }
    }
  }

  Future<void> _clear(BuildContext context, bool history) async {
    final name = history ? '浏览足迹' : '本机收藏';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清空$name？'),
        content: Text('将删除本机的全部$name记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _save(
        context,
        history ? store.clearHistory() : store.clearFavorites(),
      );
    }
  }

  Widget _list(BuildContext context, bool history) {
    final items = history ? store.history : store.favorites;
    if (items.isEmpty) {
      return Center(
        child: MallMessage(
          icon: history ? Icons.history : Icons.star_outline,
          message: history ? '暂无浏览足迹' : '暂无本机收藏',
        ),
      );
    }
    return ListView.separated(
      key: PageStorageKey(history ? 'mall-history' : 'mall-favorites'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
      itemBuilder: (context, index) {
        final item = items[index];
        final product = item.product;
        return ListTile(
          key: ValueKey(
            'mall-saved-${history ? 'history' : 'favorite'}-${product.id}',
          ),
          onTap: () => onOpen(product),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          leading: SizedBox.square(
            dimension: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MallProductImage(url: product.imageUrl),
            ),
          ),
          title: Text(
            product.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.priceText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(DateFormat('MM-dd HH:mm').format(item.savedAt.toLocal())),
            ],
          ),
          trailing: IconButton(
            tooltip: history ? '删除这条足迹' : '取消本机收藏',
            icon: Icon(history ? Icons.close : Icons.star),
            onPressed: () => _save(
              context,
              history
                  ? store.removeHistory(product.id)
                  : store.removeFavorite(product.id),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: showHistory ? 1 : 0,
    child: AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('收藏与足迹'),
          actions: [
            PopupMenuButton<bool>(
              tooltip: '管理本机记录',
              onSelected: (history) => _clear(context, history),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: false,
                  enabled: store.favorites.isNotEmpty,
                  child: const Text('清空本机收藏'),
                ),
                PopupMenuItem(
                  value: true,
                  enabled: store.history.isNotEmpty,
                  child: const Text('清空浏览足迹'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '本机收藏 (${store.favorites.length})'),
              Tab(text: '浏览足迹 (${store.history.length})'),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('仅保存在本机，不同步到账号。价格为上次浏览时的信息，打开商品可刷新。'),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _list(context, false),
                    Column(
                      children: [
                        SwitchListTile(
                          title: const Text('记录浏览足迹'),
                          value: store.recordHistory,
                          onChanged: (value) =>
                              _save(context, store.setRecordHistory(value)),
                        ),
                        Expanded(child: _list(context, true)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
