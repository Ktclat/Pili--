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
  MallProductDetail? _detail;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Widget _summary(MallProduct product, ThemeData theme) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.priceText,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(product.title, style: theme.textTheme.titleLarge),
        if (product.subtitle?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Text(product.subtitle!),
        ],
        if (product.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in product.tags)
                Chip(label: Text(tag), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
        if (_detail?.description?.isNotEmpty == true) ...[
          const Divider(height: 32),
          Text(_detail!.description!),
        ],
        if (_detail?.properties.isNotEmpty == true) ...[
          const Divider(height: 32),
          for (final entry in _detail!.properties.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 96, child: Text(entry.key)),
                  Expanded(child: Text(entry.value)),
                ],
              ),
            ),
        ],
        if (_error != null)
          MallMessage(
            message: _error!,
            action: '重新加载详情',
            onAction: _load,
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
    final descriptionImages = _detail?.descriptionImages ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: const Text('商品详情')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          key: const ValueKey('mall-detail-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: images.isEmpty
                            ? const MallProductImage()
                            : PageView.builder(
                                itemCount: images.length,
                                itemBuilder: (context, index) =>
                                    MallProductImage(
                                      url: images[index],
                                      fit: BoxFit.contain,
                                    ),
                              ),
                      ),
                    ),
                  ),
                  if (images.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '左右滑动查看 ${images.length} 张商品图片',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  _summary(product, theme),
                ],
              ),
            ),
            if (descriptionImages.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text('商品介绍', style: theme.textTheme.titleMedium),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                sliver: SliverList.builder(
                  itemCount: descriptionImages.length,
                  itemBuilder: (context, index) => LayoutBuilder(
                    builder: (context, constraints) => Image.network(
                      descriptionImages[index],
                      width: double.infinity,
                      cacheWidth:
                          (constraints.maxWidth *
                                  MediaQuery.devicePixelRatioOf(context))
                              .ceil()
                              .clamp(1, 1600),
                      fit: BoxFit.fitWidth,
                      frameBuilder: (_, child, frame, _) => frame == null
                          ? const SizedBox(
                              height: 260,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : child,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 120,
                        child: Center(child: Text('图片暂时无法加载')),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
