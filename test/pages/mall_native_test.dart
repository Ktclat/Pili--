import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart' as loading;
import 'package:PiliPlus/http/mall.dart';
import 'package:PiliPlus/models/mall/mall.dart' as mall;
import 'package:PiliPlus/models/mall/search.dart';
import 'package:PiliPlus/utils/mall_local_store.dart';
import 'package:PiliPlus/common/widgets/main_layout.dart';
import 'package:PiliPlus/pages/mall/detail.dart';
import 'package:PiliPlus/pages/mall/view.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

late MallLocalStore _localStore;

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
  final searchOptions = <MallSearchOptions>[];
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
    MallSearchOptions options = const MallSearchOptions(),
    CancelToken? cancelToken,
  }) async {
    calls.add((query, page, 0));
    tokens.add(cancelToken);
    searchOptions.add(options);
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
  Future<void> Function(String text)? shareProduct,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: MallPage(
        repository: repository,
        localStore: _localStore,
        openOfficial: openOfficial,
        shareProduct: shareProduct,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _localStore = MallLocalStore());
  tearDown(() => _localStore.dispose());

  testWidgets(
    'saved items remain usable on a narrow screen with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      await _open(tester, repository, textScale: 1.8);
      await tester.tap(find.text('原生商品卡片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('加入本机收藏'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('本机收藏'));
      await tester.pumpAndSettle();
      expect(find.text('原生商品卡片').hitTestable(), findsOneWidget);
      expect(find.byTooltip('取消本机收藏').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'price filter sheet scrolls above the keyboard on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final repository = _Repository();
      await _open(tester, repository, textScale: 1.8);
      await tester.enterText(find.byKey(const ValueKey('mall-search')), '商品');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('价格筛选'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('应用价格区间'));
      await tester.pumpAndSettle();
      expect(find.text('应用价格区间').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('应用价格区间'));
      await tester.pumpAndSettle();
      expect(find.text('价格区间'), findsNothing);
    },
  );

  testWidgets('changing sort resets pagination and isolates an older search', (
    tester,
  ) async {
    final stale = Completer<loading.LoadingState<mall.MallPage>>();
    final repository = _Repository();
    repository.onSearch = (_, page) =>
        repository.searchOptions.last.sort == MallSort.relevance
        ? stale.future
        : _page([_second], page: page, hasNext: page == 1);
    await _open(tester, repository);
    await tester.enterText(find.byKey(const ValueKey('mall-search')), '商品');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.tap(find.byTooltip('搜索排序'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('销量优先').last);
    await tester.pumpAndSettle();
    expect(repository.searchOptions.last.sort, MallSort.sales);
    expect(repository.calls.last, ('商品', 1, 0));
    expect(repository.tokens[1]!.isCancelled, isTrue);
    stale.complete(_page([_product]));
    await tester.pumpAndSettle();
    expect(find.text('原生商品卡片'), findsNothing);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(repository.calls.last, ('商品', 2, 0));
    expect(repository.searchOptions.last.sort, MallSort.sales);
  });

  testWidgets(
    'price sheet rejects invalid bounds, applies exact amounts and resets',
    (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      await tester.enterText(find.byKey(const ValueKey('mall-search')), '商品');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('价格筛选'));
      await tester.pumpAndSettle();
      final minimum = find.byKey(const ValueKey('mall-minimum-price'));
      final maximum = find.byKey(const ValueKey('mall-maximum-price'));
      await tester.enterText(minimum, '100');
      await tester.enterText(maximum, '50');
      await tester.tap(find.text('应用价格区间'));
      await tester.pumpAndSettle();
      expect(find.text('最高价不能低于最低价'), findsOneWidget);
      expect(repository.searchOptions, hasLength(1));
      await tester.enterText(minimum, '-1');
      await tester.tap(find.text('应用价格区间'));
      await tester.pumpAndSettle();
      expect(find.text('请输入非负金额，最多两位小数'), findsOneWidget);
      await tester.enterText(minimum, '50.29');
      await tester.enterText(maximum, '100');
      await tester.tap(find.text('应用价格区间'));
      await tester.pumpAndSettle();
      expect(repository.searchOptions.last.minimumFen, 5029);
      expect(repository.searchOptions.last.maximumFen, 10000);
      await tester.ensureVisible(find.text('重置筛选'));
      await tester.tap(find.text('重置筛选'));
      await tester.pumpAndSettle();
      expect(repository.searchOptions.last.isDefault, isTrue);
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(find.text('综合排序'), findsNothing);
      expect(repository.calls.last.$1, 'home');
    },
  );

  testWidgets(
    'favorites reopen native details and refresh shared local snapshots',
    (tester) async {
      final repository = _Repository();
      await _open(tester, repository);
      await tester.tap(find.text('原生商品卡片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('加入本机收藏'));
      await tester.pumpAndSettle();
      expect(_localStore.favorites, hasLength(1));
      expect(find.byTooltip('取消本机收藏'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('本机收藏'));
      await tester.pumpAndSettle();
      expect(find.text('本机收藏 (1)'), findsOneWidget);
      repository.onDetail = (_) => const loading.Success(
        mall.MallProductDetail(
          product: mall.MallProduct(
            id: '123',
            title: '刷新后的商品',
            priceText: '商品价¥115',
          ),
        ),
      );
      await tester.tap(find.text('原生商品卡片'));
      await tester.pumpAndSettle();
      expect(find.byType(MallProductDetailPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('刷新后的商品'), findsOneWidget);
      expect(find.text('商品价¥115'), findsOneWidget);
      await tester.tap(find.byTooltip('取消本机收藏'));
      await tester.pumpAndSettle();
      expect(find.text('暂无本机收藏'), findsOneWidget);
      expect(_localStore.history, hasLength(1));
    },
  );

  testWidgets(
    'history can pause and clear with confirmation while favorites remain',
    (tester) async {
      await _localStore.visit(_product);
      await _localStore.toggleFavorite(_product);
      final repository = _Repository();
      await _open(tester, repository);
      await tester.tap(find.byTooltip('浏览足迹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记录浏览足迹'));
      await tester.pumpAndSettle();
      expect(_localStore.recordHistory, isFalse);
      await tester.tap(find.byTooltip('管理本机记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空浏览足迹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(_localStore.history, hasLength(1));
      await tester.tap(find.byTooltip('管理本机记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空浏览足迹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('暂无浏览足迹'), findsOneWidget);
      expect(_localStore.favorites, hasLength(1));
    },
  );

  testWidgets('sharing and copying preserve the special official product route', (
    tester,
  ) async {
    const url =
        'https://mall.bilibili.com/neul/index.html?page=magic-detail_detail&itemsId=123';
    const special = mall.MallProduct(
      id: '123',
      title: '特别商品',
      priceText: '¥39',
      officialUrl: url,
    );
    final shared = <String>[];
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repository = _Repository()..onHome = (_, _) => _page([special]);
    await _open(
      tester,
      repository,
      shareProduct: (text) async => shared.add(text),
    );
    await tester.tap(find.text('特别商品'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('分享与复制链接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享商品'));
    await tester.pumpAndSettle();
    expect(shared.single, endsWith('\n$url'));
    await tester.tap(find.byTooltip('分享与复制链接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制商品链接'));
    await tester.pumpAndSettle();
    expect(copied, url);
  });
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
                  localStore: _localStore,
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
      MaterialApp(
        home: MallPage(repository: repository, localStore: _localStore),
      ),
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
      await tester.drag(
        find.byKey(const ValueKey('mall-detail-scroll')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(find.text('下一页商品').hitTestable(), findsOneWidget);
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
        MaterialApp(
          home: MallPage(repository: repository, localStore: _localStore),
        ),
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
