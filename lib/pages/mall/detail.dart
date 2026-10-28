import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart' as loading;
import 'package:PiliPlus/http/mall.dart';
import 'package:PiliPlus/models/mall/mall.dart';
import 'package:PiliPlus/pages/mall/widgets.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

class MallProductDetailPage extends StatefulWidget {
  const MallProductDetailPage({
    super.key,
    required this.product,
    required this.repository,
    this.openOfficial,
  });

  final MallProduct product;
  final MallRepository repository;
  final Future<void> Function(String url)? openOfficial;

  @override
  State<MallProductDetailPage> createState() => _MallProductDetailPageState();
}

class _MallProductDetailPageState extends State<MallProductDetailPage> {
  CancelToken? _cancelToken;
  CancelToken? _relatedCancel;
  final _relatedSearch = TextEditingController();
  final _detailScroll = ScrollController();
  final _relatedProducts = <MallProduct>[];
  int _relatedGeneration = 0;
  int _relatedPage = 0;
  String _relatedQuery = '';
  String? _relatedError;
  bool _relatedLoaded = false;
  bool _relatedLoading = false;
  bool _relatedHasNext = false;
  bool _relatedMoreFailed = false;
  int _imageIndex = 0;
  MallProductDetail? _detail;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _relatedSearch.text = String.fromCharCodes(
      widget.product.title.runes.take(10),
    ).trim();
    unawaited(_load());
  }

  Future<void> _load() async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.detail(
        widget.product.id,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (result case loading.Success<MallProductDetail>(:final response)) {
          _detail = response;
          _imageIndex = 0;
        } else {
          _error = mallErrorMessage(result);
        }
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '商品详情加载失败，请重试');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  /// Read-only search is opt-in: opening a detail page does not make
  /// additional product requests or send the user's account credentials.
  Future<void> _findMore({bool nextPage = false}) async {
    if (nextPage && (_relatedLoading || !_relatedHasNext)) return;
    final query = nextPage ? _relatedQuery : _relatedSearch.text.trim();
    if (query.isEmpty) {
      setState(() => _relatedError = '请填写商品关键词');
      return;
    }
    if (!nextPage) {
      _relatedCancel?.cancel();
      _relatedCancel = CancelToken();
      ++_relatedGeneration;
    }
    final generation = _relatedGeneration;
    final page = nextPage ? _relatedPage + 1 : 1;
    setState(() {
      _relatedLoading = true;
      _relatedError = null;
      _relatedMoreFailed = false;
      if (!nextPage) {
        _relatedLoaded = true;
        _relatedQuery = query;
        _relatedPage = 0;
        _relatedHasNext = false;
        _relatedProducts.clear();
      }
    });
    try {
      final result = await widget.repository.search(
        query,
        page: page,
        cancelToken: _relatedCancel,
      );
      if (!mounted || generation != _relatedGeneration) return;
      setState(() {
        if (result case loading.Success<MallPage>(:final response)) {
          final ids = _relatedProducts.map((item) => item.id).toSet()
            ..add(widget.product.id);
          final added = response.items
              .where((item) => ids.add(item.id))
              .toList();
          _relatedProducts.addAll(added);
          _relatedPage = response.page;
          _relatedHasNext = response.hasNext && added.isNotEmpty;
        } else {
          _relatedError = mallErrorMessage(result);
          _relatedMoreFailed = nextPage;
        }
      });
    } catch (_) {
      if (mounted && generation == _relatedGeneration) {
        setState(() {
          _relatedError = '商品搜索失败，请稍后重试';
          _relatedMoreFailed = nextPage;
        });
      }
    } finally {
      if (mounted && generation == _relatedGeneration) {
        setState(() => _relatedLoading = false);
      }
    }
  }

  void _openProduct(MallProduct product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MallProductDetailPage(
          product: product,
          repository: widget.repository,
          openOfficial: widget.openOfficial,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _relatedCancel?.cancel();
    _relatedSearch.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  void _showImage(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('查看商品图片'),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            leading: IconButton(
              tooltip: '关闭图片',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text(
                  '图片暂时无法加载',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _gallery(List<String> images) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (images.isEmpty)
              const MallProductImage()
            else
              PageView.builder(
                key: ValueKey('mall-gallery-' + images.join('|')),
                itemCount: images.length,
                onPageChanged: (index) => setState(() => _imageIndex = index),
                itemBuilder: (context, index) => Semantics(
                  label: '点按放大商品图片',
                  button: true,
                  child: InkWell(
                    onTap: () => _showImage(images[index]),
                    child: MallProductImage(
                      url: images[index],
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            if (images.length > 1)
              Positioned(
                bottom: 12,
                right: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: Text(
                      (_imageIndex + 1).toString() + ' / ' +
                          images.length.toString(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _sectionHeading(String title, ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _property(String name, String value, ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            name,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(value)),
      ],
    ),
  );

  Widget _summary(MallProduct product, ThemeData theme) {
    final detail = _detail;
    final tags = <String>{...widget.product.tags, ...product.tags};
    final deposit = detail?.depositFen;
    final shop = detail?.shopName;
    final promotion = detail?.promotion;
    final delivery = detail?.deliveryEstimate;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                product.priceText,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                product.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (product.subtitle?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(product.subtitle!),
              ],
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags.take(8))
                      Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              if (deposit != null && deposit > 0) ...[
                const SizedBox(height: 14),
                Card.filled(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _property(
                      '预售定金',
                      '¥' + (deposit ~/ 100).toString() + '.' +
                          (deposit % 100).toString().padLeft(2, '0') +
                          '（非全款）',
                      theme,
                    ),
                  ),
                ),
              ],
              if (promotion != null) ...[
                const SizedBox(height: 12),
                Card.filled(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _property('官方活动', promotion, theme),
                  ),
                ),
              ],
              if (delivery != null) ...[
                const SizedBox(height: 12),
                _property('预计发货', delivery, theme),
              ],
              if (shop != null) ...[
                const SizedBox(height: 16),
                Card.outlined(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: ClipOval(
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: MallProductImage(url: detail?.shopAvatarUrl),
                      ),
                    ),
                    title: Text(shop),
                    subtitle: const Text('会员购官方店铺信息'),
                    trailing: const Icon(Icons.storefront_outlined),
                  ),
                ),
              ],
              if (detail?.properties.isNotEmpty == true) ...[
                const SizedBox(height: 24),
                _sectionHeading('商品规格与信息', theme),
                for (final entry in detail!.properties.entries)
                  if (entry.key != '店铺' &&
                      entry.key != '官方活动' &&
                      entry.key != '预计发货' &&
                      entry.key != '定金')
                    _property(entry.key, entry.value, theme),
              ],
              if (detail?.description?.isNotEmpty == true &&
                  detail!.descriptionParts.isEmpty) ...[
                const SizedBox(height: 22),
                _sectionHeading('商品介绍', theme),
                SelectableText(detail!.description!),
              ],
              if (_error != null)
                MallMessage(
                  message: _error!,
                  action: '重新加载详情',
                  onAction: _load,
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<MallDescriptionPart> get _descriptionParts {
    final detail = _detail;
    if (detail == null) return const [];
    if (detail.descriptionParts.isNotEmpty) return detail.descriptionParts;
    return [
      if (detail.description != null)
        MallDescriptionPart.text(detail.description!),
      for (final image in detail.descriptionImages)
        MallDescriptionPart.image(image),
    ];
  }

  Widget _descriptionPart(MallDescriptionPart part) {
    if (part.text case final text?) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SelectableText(text),
      );
    }
    if (part.imageUrl case final url?) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: LayoutBuilder(
          builder: (context, constraints) => Image.network(
            url,
            width: double.infinity,
            cacheWidth:
                (constraints.maxWidth *
                        MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(1, 1600),
            fit: BoxFit.fitWidth,
            frameBuilder: (_, child, frame, _) => frame == null
                ? const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : child,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 100,
              child: Center(child: Text('详情图片暂时无法加载')),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _moreProducts(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeading('继续逛会员购', theme),
            Text(
              '在应用内搜索、浏览更多商品和完整详情，购买时才打开官方页面。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('mall-related-search'),
              controller: _relatedSearch,
              maxLength: 100,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => unawaited(_findMore()),
              decoration: InputDecoration(
                labelText: '搜索其他商品',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: '搜索更多商品',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _relatedLoading
                      ? null
                      : () => unawaited(_findMore()),
                ),
              ),
            ),
            if (_relatedLoading) const LinearProgressIndicator(),
            if (_relatedError != null)
              MallMessage(
                message: _relatedError!,
                action: _relatedMoreFailed ? '重试加载更多' : '重试搜索',
                onAction: () => unawaited(
                  _findMore(nextPage: _relatedMoreFailed),
                ),
              ),
            if (_relatedLoaded &&
                !_relatedLoading &&
                _relatedError == null &&
                _relatedProducts.isEmpty)
              const MallMessage(message: '没有找到其他商品，请尝试其他关键词'),
            if (_relatedProducts.isNotEmpty) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      (constraints.maxWidth / 180).floor().clamp(2, 4);
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: width + 136 * scale.clamp(1, 2),
                    ),
                    itemCount: _relatedProducts.length,
                    itemBuilder: (_, index) => MallProductCard(
                      product: _relatedProducts[index],
                      onTap: () => _openProduct(_relatedProducts[index]),
                    ),
                  );
                },
              ),
              if (_relatedHasNext)
                Center(
                  child: OutlinedButton(
                    onPressed: _relatedLoading
                        ? null
                        : () => unawaited(_findMore(nextPage: true)),
                    child: const Text('加载更多商品'),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = _descriptionParts;
    final product = _detail?.product ?? widget.product;
    final images = _detail?.images.isNotEmpty == true
        ? _detail!.images
        : [if (product.imageUrl?.isNotEmpty == true) product.imageUrl!];
    // Preserve the API's original purchase route for blind boxes and other
    // special products; their checkout does not use the generic detail page.
    final official = Uri.tryParse(
      widget.product.officialUrl ?? product.officialUrl ?? '',
    );
    final canBuy =
        official != null &&
        official.scheme == 'https' &&
        official.host == 'mall.bilibili.com' &&
        official.port == 443 &&
        official.userInfo.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('商品详情'),
        actions: [
          IconButton(
            tooltip: '搜索更多商品',
            icon: const Icon(Icons.search),
            onPressed: () {
              if (_detailScroll.hasClients) {
                unawaited(_detailScroll.animateTo(
                  _detailScroll.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                ));
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          key: const ValueKey('mall-detail-scroll'),
          controller: _detailScroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  _gallery(images),
                  _summary(product, theme),
                ],
              ),
            ),
            if (parts.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: _sectionHeading('商品图文详情', theme),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: parts.length,
                  itemBuilder: (context, index) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: _descriptionPart(parts[index]),
                    ),
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(child: _moreProducts(theme)),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '购买、订单与支付在官方页面完成，规格、库存和最终价格以官方为准。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canBuy
                      ? () =>
                            widget.openOfficial?.call(official.toString()) ??
                            PageUtils.launchURL(official.toString())
                      : null,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('前往官方购买'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
