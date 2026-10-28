import 'package:PiliPlus/http/loading_state.dart' as loading;
import 'package:PiliPlus/models/mall/mall.dart';
import 'package:material_ui/material_ui.dart';

String mallErrorMessage(Object result) {
  if (result case loading.Error(:final errMsg)
      when errMsg?.isNotEmpty == true) {
    return errMsg!;
  }
  return '商品加载失败，请稍后重试';
}

class MallMessage extends StatelessWidget {
  const MallMessage({
    super.key,
    required this.message,
    this.icon,
    this.action,
    this.onAction,
  });

  final String message;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 44, color: ColorScheme.of(context).outline),
          const SizedBox(height: 12),
        ],
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

class MallProductImage extends StatelessWidget {
  const MallProductImage({super.key, this.url, this.fit = BoxFit.cover});

  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => ColoredBox(
      color: ColorScheme.of(context).surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          size: 40,
          color: ColorScheme.of(context).outline,
        ),
      ),
    );
    return url?.isNotEmpty == true
        ? LayoutBuilder(
            builder: (context, constraints) => Image.network(
              url!,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              cacheWidth:
                  (constraints.maxWidth *
                          MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 1600),
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => placeholder(),
            ),
          )
        : placeholder();
  }
}

class MallProductCard extends StatelessWidget {
  const MallProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  final MallProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('mall-product-${product.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: MallProductImage(url: product.imageUrl),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (product.tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        product.tags.take(2).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      product.priceText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
