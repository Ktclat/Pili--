import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart' as loading;
import 'package:PiliPlus/http/mall.dart';
import 'package:PiliPlus/models/mall/mall.dart' as mall;
import 'package:PiliPlus/pages/mall/detail.dart';
import 'package:PiliPlus/pages/mall/widgets.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

/// Native catalog backed by the official mall's product APIs.
class MallPage extends StatefulWidget {
  const MallPage({
    super.key,
    this.repository,
    this.openOfficial,
    this.embeddedInNavigation = false,
  });

  final MallRepository? repository;
  final Future<void> Function(String url)? openOfficial;
  final bool embeddedInNavigation;

  @override
  State<MallPage> createState() => _MallPageState();
}

class _MallPageState extends State<MallPage>
    with AutomaticKeepAliveClientMixin {
  late final MallRepository _repository = widget.repository ?? MallHttp();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _products = <mall.MallProduct>[];
  List<mall.MallCategory> _categories = const [];
  CancelToken? _cancelToken;
  String _query = '';
  int _categoryId = 0;
  int _page = 0;
  int _generation = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = false;
  String? _error;
  String? _moreError;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load(reset: true));
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 360 && _moreError == null) {
      unawaited(_load());
    }
  }

  Future<void> _load({bool reset = false, bool clear = false}) async {
    if (!reset && (_loading || _loadingMore || !_hasNext)) return;
    if (reset) {
      _cancelToken?.cancel();
      _cancelToken = CancelToken();
      _generation++;
    }
    final generation = _generation;
    final nextPage = reset ? 1 : _page + 1;
    setState(() {
      if (reset) {
        _loading = true;
        _loadingMore = false;
        _page = 0;
        _hasNext = false;
        _error = null;
        if (clear) _products.clear();
      } else {
        _loadingMore = true;
      }
      _moreError = null;
    });
    try {
      final result = _query.isEmpty
          ? await _repository.home(
              page: nextPage,
              categoryId: _categoryId,
              cancelToken: _cancelToken,
            )
          : await _repository.search(
              _query,
              page: nextPage,
              cancelToken: _cancelToken,
            );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (result case loading.Success<mall.MallPage>(:final response)) {
          if (reset) _products.clear();
          final ids = _products.map((product) => product.id).toSet();
          final additions = response.items
              .where((product) => ids.add(product.id))
              .toList();
          _products.addAll(additions);
          if (_query.isEmpty && response.categories.isNotEmpty) {
            _categories = response.categories;
          }
          _page = response.page;
          _hasNext = response.hasNext && (reset || additions.isNotEmpty);
        } else {
          final message = mallErrorMessage(result);
          if (reset) {
            _error = message;
          } else {
            _moreError = message;
          }
        }
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (reset) {
          _error = '商品加载失败，请检查网络后重试';
        } else {
          _moreError = '更多商品加载失败，请重试';
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _submit(String value) {
    FocusScope.of(context).unfocus();
    _query = value.trim();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_load(reset: true, clear: true));
  }

  void _selectCategory(int id) {
    if (_categoryId == id) return;
    _categoryId = id;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_load(reset: true, clear: true));
  }

  void _openProduct(mall.MallProduct product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MallProductDetailPage(
          product: product,
          repository: _repository,
          openOfficial: widget.openOfficial,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    if (widget.repository == null) {
      if (_repository case final MallHttp repository) repository.close();
    }
    _search.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Scaffold(
      primary: !widget.embeddedInNavigation,
      appBar: AppBar(
        primary: !widget.embeddedInNavigation,
        title: const Text('会员购'),
      ),
      body: SafeArea(
        top: false,
        left: !widget.embeddedInNavigation,
        right: !widget.embeddedInNavigation,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                key: const ValueKey('mall-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索会员购商品',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  prefixIcon: IconButton(
                    tooltip: '搜索商品',
                    onPressed: () => _submit(_search.text),
                    icon: const Icon(Icons.search),
                  ),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            _search.clear();
                            _submit('');
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            if (_query.isEmpty && _categories.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  spacing: 8,
                  children: [
                    if (!_categories.any((category) => category.id == 0))
                      ChoiceChip(
                        label: const Text('推荐'),
                        selected: _categoryId == 0,
                        onSelected: (_) => _selectCategory(0),
                      ),
                    for (final category in _categories)
                      ChoiceChip(
                        label: Text(category.id == 0 ? '推荐' : category.name),
                        selected: category.id == _categoryId,
                        onSelected: (_) => _selectCategory(category.id),
                      ),
                  ],
                ),
              ),
            if (_loading && _products.isNotEmpty)
              const LinearProgressIndicator(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: CustomScrollView(
                  key: const PageStorageKey('mall-products'),
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (_products.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : MallMessage(
                                icon: _error == null
                                    ? Icons.shopping_bag_outlined
                                    : Icons.cloud_off_outlined,
                                message:
                                    _error ??
                                    (_query.isEmpty ? '暂无商品' : '没有找到相关商品'),
                                action: _error == null ? null : '重新加载',
                                onAction: () => _load(reset: true),
                              ),
                      )
                    else ...[
                      if (_error != null)
                        SliverToBoxAdapter(
                          child: MallMessage(
                            message: _error!,
                            action: '重新加载',
                            onAction: () => _load(reset: true),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final columns = (constraints.crossAxisExtent / 180)
                                .floor()
                                .clamp(2, 5);
                            final width =
                                (constraints.crossAxisExtent -
                                    (columns - 1) * 12) /
                                columns;
                            final textScale = MediaQuery.textScalerOf(
                              context,
                            ).scale(1);
                            return SliverGrid.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    mainAxisExtent:
                                        width + 136 * textScale.clamp(1, 2),
                                  ),
                              itemCount: _products.length,
                              itemBuilder: (context, index) => MallProductCard(
                                product: _products[index],
                                onTap: () => _openProduct(_products[index]),
                              ),
                            );
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          // MainLayout paints navigation over its full-height
                          // body. Keep the last action scrollable above it.
                          padding: EdgeInsets.only(
                            bottom: widget.embeddedInNavigation ? 120 : 20,
                          ),
                          child: _loadingMore
                              ? const Center(child: CircularProgressIndicator())
                              : _moreError != null
                              ? MallMessage(
                                  message: _moreError!,
                                  action: '重试加载更多',
                                  onAction: _load,
                                )
                              : _hasNext
                              ? Center(
                                  child: TextButton(
                                    onPressed: _load,
                                    child: const Text('加载更多'),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    '已经到底了',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
