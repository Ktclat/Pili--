import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart' as loading;
import 'package:PiliPlus/http/mall.dart';
import 'package:PiliPlus/models/mall/mall.dart' as mall;
import 'package:PiliPlus/common/widgets/main_layout.dart';
import 'package:PiliPlus/pages/mall/detail.dart';
import 'package:PiliPlus/pages/mall/view.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _product = mall.MallProduct(
  id: '123',
  title: '原生商品卡片',
  priceText: '定金¥17.25',
  officialUrl: 'https://mall.bilibili.com/detail.html?itemsId=123',
);
const _second = mall.MallProduct(
  id: '456',
  title: '下一页商品',
  priceText: '¥69起',
);

loading.Success<mall.MallPage> _page(
  List<mall.MallProduct> items, {
  int page = 1,
  bool hasNext = false,
  List<mall.MallCategory> categories = const [],
}) => loading.Success(
  mall.MallPage(
    items: items,
    page: page,
    hasNext: hasNext,
    categories: categories,
  ),
);

class _Repository implements MallRepository {
  final calls = <(String, int, int)>[];
  final tokens = <CancelToken?>[];
  FutureOr<loading.LoadingState<mall.MallPage>> Function(
    int page,
    int category,
  )?
  onHome;
  FutureOr<loading.LoadingState<mall.MallPage>> Function(
    String query,
    int page,
  )?
  onSearch;
  FutureOr<loading.LoadingState<mall.MallProductDetail>> Function(String id)?
  onDetail;

  @override
  Future<loading.LoadingState<mall.MallPage>> home({
    int page = 1,
    int categoryId = 0,
    CancelToken? cancelToken,
  }) async {
    calls.add(('home', page, categoryId));
    tokens.add(cancelToken);
    return await onHome?.call(page, categoryId) ?? _page([_product]);
  }

  @override
  Future<loading.LoadingState<mall.MallPage>> search(
    String query, {
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    calls.add((query, page, 0));
    tokens.add(cancelToken);
    return await onSearch?.call(query, page) ?? _page([_second]);
  }

  @override
  Future<loading.LoadingState<mall.MallProductDetail>> detail(
    String id, {
    CancelToken? cancelToken,
  }) async {
    calls.add(('detail:$id', 0, 0));
    tokens.add(cancelToken);
    return await onDetail?.call(id) ??
        const loading.Success(mall.MallProductDetail(product: _product));
  }
}

Future<void> _open(
  WidgetTester tester,
  _Repository repository, {
  Future<void> Function(String url)? openOfficial,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: MallPage(repository: repository, openOfficial: openOfficial),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'embedded catalog uses outer insets and clears navigation overlay',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository()
        ..onHome = (page, _) => page == 1
            ? _page(
                List.generate(
                  6,
                  (index) => mall.MallProduct(
                    id: '${index + 1}',
                    title: '商品 $index',
                    priceText: '¥10',
                  ),
                ),
                hasNext: true,
              )
            : const loading.Error('加载更多失败');
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              padding: EdgeInsets.only(top: 24, bottom: 24),
              viewPadding: EdgeInsets.only(top: 24, bottom: 24),
            ),
            child: MainLayout(
              sideBar: null,
              bottomNav: const SizedBox(width: 400, height: 104),
              body: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: MallPage(
                  repository: repository,
                  embeddedInNavigation: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(AppBar)).height, kToolbarHeight);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('重试加载更多'), findsOneWidget);
      expect(tester.getRect(find.text('重试加载更多')).top, greaterThan(80));
      expect(
        tester.getRect(find.text('重试加载更多')).bottom,
        lessThanOrEqualTo(696),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opens a built-in native catalog immediately and preserves price labels',
    (
      tester,
    ) async {
      final repository = _Repository();
      await _open(tester, repository);

      expect(repository.calls, [('home', 1, 0)]);
      expect(find.text('原生商品卡片'), findsOneWidget);
      expect(find.text('定金¥17.25'), findsOneWidget);
      expect(find.text('下载并启用'), findsNothing);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(SliverGrid), findsOneWidget);
    },
  );

  testWidgets(
    'failed first page has a working retry and an empty result stays empty',
    (
      tester,
    ) async {
      final repository = _Repository()
        ..onHome = (_, _) => const loading.Error('会员购暂时不可用');
      await _open(tester, repository);
      expect(find.text('会员购暂时不可用'), findsOneWidget);
      expect(find.text('原生商品卡片'), findsNothing);

      repository.onHome = (_, _) => _page([]);
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(repository.calls, [('home', 1, 0), ('home', 1, 0)]);
      expect(find.text('暂无商品'), findsOneWidget);
    },
  );

  testWidgets('late home data cannot replace a newer search result', (
    tester,
  ) async {
    final home = Completer<loading.LoadingState<mall.MallPage>>();
    final repository = _Repository()..onHome = (_, _) => home.future;
    await tester.pumpWidget(
      MaterialApp(home: MallPage(repository: repository)),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const ValueKey('mall-search')), '初音未来');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(repository.tokens.first!.isCancelled, isTrue);
    expect(find.text('下一页商品'), findsOneWidget);

    home.complete(_page([_product]));
    await tester.pumpAndSettle();
    expect(find.text('原生商品卡片'), findsNothing);
    expect(find.text('下一页商品'), findsOneWidget);

    repository.onHome = (_, _) => _page([_product]);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('原生商品卡片'), findsOneWidget);
  });

  testWidgets(
    'pagination retry retains products and removes duplicate item IDs',
    (
      tester,
    ) async {
      var failNextPage = true;
      final repository = _Repository()
        ..onHome = (page, _) => page == 1
            ? _page([_product], hasNext: true)
            : failNextPage
            ? const loading.Error('加载更多失败')
            : _page([_product, _second], page: 2);
      await _open(tester, repository);

      await tester.ensureVisible(find.text('加载更多'));
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('原生商品卡片'), findsOneWidget);
      expect(find.text('重试加载更多'), findsOneWidget);

      failNextPage = false;
      await tester.tap(find.text('重试加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('原生商品卡片'), findsOneWidget);
      expect(find.text('下一页商品'), findsOneWidget);
      expect(repository.calls.where((call) => call.$2 == 2).length, 2);
    },
  );

  testWidgets(
    'only returned categories are selectable and use their actual IDs',
    (
      tester,
    ) async {
      final repository = _Repository()
        ..onHome = (_, category) => _page(
          category == 7 ? [_second] : [_product],
          categories: const [mall.MallCategory(id: 7, name: '手办')],
        );
      await _open(tester, repository);

      await tester.tap(find.text('手办'));
      await tester.pumpAndSettle();
      expect(repository.calls.last, ('home', 1, 7));
      expect(find.text('下一页商品'), findsOneWidget);
      expect(find.text('原生商品卡片'), findsNothing);
    },
  );

  testWidgets(
    'detail stays native and opens official checkout only after a tap',
    (
      tester,
    ) async {
      const detailProduct = mall.MallProduct(
        id: '123',
        title: '官方商品详情名称',
        priceText: '商品价¥115',
        officialUrl: 'https://mall.bilibili.com/detail.html?itemsId=123',
      );
      final opened = <String>[];
      final repository = _Repository()
        ..onDetail = (_) => const loading.Success(
          mall.MallProductDetail(
            product: detailProduct,
            description: '官方商品介绍',
            properties: {'定金': '¥17.25', '店铺': '官方店铺'},
          ),
        );
      await _open(
        tester,
        repository,
        openOfficial: (url) async => opened.add(url),
      );

      await tester.tap(find.text('原生商品卡片'));
      await tester.pumpAndSettle();
      expect(find.byType(MallProductDetailPage), findsOneWidget);
      expect(repository.calls.last, ('detail:123', 0, 0));
      expect(opened, isEmpty);
      await tester.drag(
        find.byKey(const ValueKey('mall-detail-scroll')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(find.text('商品价¥115'), findsOneWidget);
      expect(find.text('定金'), findsOneWidget);
      expect(find.text('官方店铺'), findsOneWidget);

      await tester.tap(find.text('前往官方购买'));
      await tester.pumpAndSettle();
      expect(opened, ['https://mall.bilibili.com/detail.html?itemsId=123']);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('原生商品卡片'), findsOneWidget);
    },
  );

  testWidgets(
    'native detail can search and open another product without a web page',
    (tester) async {
      final opened = <String>[];
      final repository = _Repository();
      await _open(
        tester,
        repository,
        openOfficial: (url) async => opened.add(url),
      );
      await tester.tap(find.text('原生商品卡片'));
      await tester.pumpAndSettle();
      expect(repository.calls.where((call) => call.$1 == '下一页商品'), isEmpty);

      await tester.tap(find.byTooltip('搜索更多商品').first);
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('mall-related-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, '商品');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(repository.calls, contains(('商品', 1, 0)));
      expect(find.text('下一页商品'), findsOneWidget);
      await tester.ensureVisible(find.text('下一页商品'));
      await tester.tap(find.text('下一页商品'));
      await tester.pumpAndSettle();
      expect(repository.calls.last, ('detail:456', 0, 0));
      expect(find.byType(MallProductDetailPage), findsOneWidget);
      expect(opened, isEmpty);
    },
  );

  testWidgets(
    'verified preorder fields appear natively without exposing a fake checkout',
    (tester) async {
      final repository = _Repository()
        ..onDetail = (_) => const loading.Success(
          mall.MallProductDetail(
            product: _product,
            shopName: '会员购官方店铺',
            promotion: '官方折扣活动',
            depositFen: 1725,
            deliveryEstimate: '2027年04月',
            properties: {'材质': 'PVC'},
          ),
        );
      await _open(tester, repository);
      await tester.tap(find.text('原生商品卡片'));
      await tester.pumpAndSettle();
      expect(find.text('会员购官方店铺'), findsOneWidget);
      expect(find.text('官方折扣活动'), findsOneWidget);
      expect(find.textContaining('17.25'), findsWidgets);
      expect(find.text('2027年04月'), findsOneWidget);
      expect(find.text('材质'), findsOneWidget);
      expect(find.text('PVC'), findsOneWidget);
    },
  );

  testWidgets(
    'disposing the catalog cancels a request and ignores its late result',
    (
      tester,
    ) async {
      final response = Completer<loading.LoadingState<mall.MallPage>>();
      final repository = _Repository()..onHome = (_, _) => response.future;
      await tester.pumpWidget(
        MaterialApp(home: MallPage(repository: repository)),
      );
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(repository.tokens.single!.isCancelled, isTrue);
      response.complete(_page([_product]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate-only pages stop pagination and retain existing categories',
    (
      tester,
    ) async {
      final repository = _Repository()
        ..onHome = (page, _) => _page(
          [_product],
          page: page,
          hasNext: true,
          categories: page == 1
              ? const [mall.MallCategory(id: 7, name: '手办')]
              : const [],
        );
      await _open(tester, repository);

      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('加载更多'), findsNothing);
      expect(find.text('手办'), findsOneWidget);
      expect(find.text('原生商品卡片'), findsOneWidget);
      expect(repository.calls, [('home', 1, 0), ('home', 2, 0)]);
    },
  );

  testWidgets(
    'a failed pull refresh retains existing products and offers retry',
    (
      tester,
    ) async {
      final repository = _Repository();
      await _open(tester, repository);
      repository.onHome = (_, _) => const loading.Error('网络暂时不可用');

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(repository.calls.length, 2);
      expect(find.text('原生商品卡片'), findsOneWidget);
      expect(find.text('网络暂时不可用'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
    },
  );

  testWidgets('failed detail can retry without fabricating product details', (
    tester,
  ) async {
    final repository = _Repository()
      ..onDetail = (_) => const loading.Error('详情暂时不可用');
    await _open(tester, repository);
    await tester.tap(find.text('原生商品卡片'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重新加载详情'));
    await tester.pumpAndSettle();
    expect(find.text('详情暂时不可用'), findsOneWidget);

    repository.onDetail = (_) => const loading.Success(
      mall.MallProductDetail(product: _product, description: '实际返回的商品介绍'),
    );
    await tester.tap(find.text('重新加载详情'));
    await tester.pumpAndSettle();
    expect(find.text('详情暂时不可用'), findsNothing);
    expect(find.text('实际返回的商品介绍'), findsOneWidget);
  });

  testWidgets(
    'checkout rejects non-mall hosts even when they belong to bilibili',
    (
      tester,
    ) async {
      const invalidProduct = mall.MallProduct(
        id: '123',
        title: '原生商品卡片',
        priceText: '¥69',
        officialUrl: 'https://www.bilibili.com/video/BV1xx411c7mD',
      );
      final repository = _Repository()
        ..onHome = ((_, _) => _page([invalidProduct]))
        ..onDetail = ((_) => const loading.Success(
          mall.MallProductDetail(product: invalidProduct),
        ));
      final opened = <String>[];
      await _open(
        tester,
        repository,
        openOfficial: (url) async => opened.add(url),
      );
      await tester.tap(find.text('原生商品卡片'));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) => widget is FilledButton && widget.onPressed == null,
        ),
        findsOneWidget,
      );
      expect(opened, isEmpty);
    },
  );

  testWidgets(
    'narrow cards retain presale tags with enlarged text without overflow',
    (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const product = mall.MallProduct(
        id: '123',
        title: '预售长标题商品用于检查文字放大和窄屏的原生商品卡片',
        priceText: '定金¥17.25',
        tags: ['预售', '惊喜赏'],
      );
      final repository = _Repository()..onHome = (_, _) => _page([product]);
      await _open(tester, repository, textScale: 1.8);

      expect(find.text('预售 · 惊喜赏'), findsOneWidget);
      expect(find.text('定金¥17.25'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail preserves special official purchase routes after loading',
    (
      tester,
    ) async {
      const product = mall.MallProduct(
        id: '123',
        title: '特别商品',
        priceText: '¥69',
        officialUrl: 'https://mall.bilibili.com/neul/index.html?page=magic-detail_detail&itemsId=123',
      );
      final repository = _Repository()..onHome = (_, _) => _page([product]);
      final opened = <String>[];
      await _open(
        tester,
        repository,
        openOfficial: (url) async => opened.add(url),
      );
      await tester.tap(find.text('特别商品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('前往官方购买'));
      await tester.pumpAndSettle();

      expect(opened, [product.officialUrl]);
    },
  );
}
