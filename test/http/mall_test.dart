import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/mall.dart';
import 'package:PiliPlus/models/mall/mall.dart';
import 'package:PiliPlus/models/mall/search.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Reduced, real public responses captured from the official mall on 2026-10-27.
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/mall/$name.json').readAsStringSync())
        as Map<String, dynamic>;

class _Adapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  bool closed = false;

  _Adapter(this.respond);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) => closed = true;
}

ResponseBody _json(Object value, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  group('official mall response models', () {
    test('new items preserve categories, yuan amounts and page boundaries', () {
      final data = _fixture('new_items')['data']['vo'] as Map<String, dynamic>;
      final page = MallPage.fromNewItems(data);
      expect(page.items, hasLength(5));
      expect(page.items.first.id, '42547033');
      expect(page.items.first.priceFen, 12870);
      expect(page.items.first.priceText, '¥128.70');
      expect(page.items.first.imageUrl, startsWith('https://i0.hdslb.com/'));
      expect(page.categories, hasLength(11));
      expect(page.categories[1].name, '手办');
      expect(page.page, 1);
      expect(page.hasNext, isTrue);

      final last = MallPage.fromNewItems({...data, 'total': 5});
      expect(last.hasNext, isFalse);
      final presale = MallProduct.fromNewItem({
        'itemsId': 13685624,
        'name': '新品预售商品',
        'price': 999.0,
        'priceDesc': ['999'],
        'preSaleTagName': '预售',
        'pricePrefix': '',
      });
      expect(presale!.tags, contains('预售'));
      expect(presale.priceText, '¥999');
    });

    test('feed totals are not mistaken for the size of the whole catalog', () {
      final data = _fixture('feed')['data']['vo'] as Map<String, dynamic>;
      final page = MallPage.fromFeed(data, requestedPage: 1, pageSize: 10);
      expect(page.items, hasLength(12));
      expect(page.hasNext, isTrue);
      expect(page.total, isNull);
      expect(page.items.first.priceFen, 1170);
      expect(page.items.first.priceText, '到手价¥11.7起');
      expect(page.items[3].priceFen, 1035);
      expect(page.items[3].priceText, '定金¥10.35');
    });

    test(
      'search uses hasNextPage rather than interpreting pageNum as current',
      () {
        final data = _fixture('search')['data'] as Map<String, dynamic>;
        final page = MallPage.fromSearch(data, requestedPage: 1);
        expect(data['pageNum'], 225);
        expect(page.page, 1);
        expect(page.total, 4500);
        expect(page.hasNext, isTrue);
        expect(page.items, hasLength(20));
        expect(page.items[2].priceText, '定金¥20.85–40.35');
        expect(page.items[2].priceFen, 2085);
        expect(page.items.first.tags, contains('惊喜赏'));
      },
    );

    test('detail separates merchandise prices from official promotions', () {
      final detail = MallProductDetail.fromJson(
        _fixture('detail')['data'] as Map<String, dynamic>,
      );
      expect(detail.product.id, '11092663');
      expect(detail.product.priceFen, 3900);
      expect(detail.product.priceText, '商品价¥39–234');
      expect(detail.properties['官方活动'], '指定商品1件3折');
      expect(detail.properties['面料'], '聚酯纤维');
      expect(detail.properties['尺寸'], '高约7cm');
      expect(detail.images, hasLength(5));
      expect(detail.descriptionImages, hasLength(10));
      expect(detail.description, isNull);
      expect(
        detail.product.officialUrl,
        'https://mall.bilibili.com/neul-next/detailuniversal/detail.html'
        '?page=detailuniversal_detail&itemsId=11092663',
      );
    });

    test('native detail preserves the official description sequence', () {
      final original = _fixture('detail')['data'] as Map<String, dynamic>;
      final detail = MallProductDetail.fromJson({
        ...original,
        'detailDescVO': const {
          'descList': [
            {
              'title': '说明标题',
              'contentList': [
                {'type': 0, 'content': '第一段文字'},
                {
                  'type': 1,
                  'content': '//i0.hdslb.com/bfs/mall/verified.png',
                },
                {'type': 0, 'content': '图片后的说明'},
              ],
            },
          ],
        },
      });
      expect(
        detail.descriptionParts.map((part) => part.text ?? part.imageUrl),
        [
          '说明标题',
          '第一段文字',
          'https://i0.hdslb.com/bfs/mall/verified.png',
          '图片后的说明',
        ],
      );
      expect(detail.shopName, '会员购');
      expect(detail.shopAvatarUrl, startsWith('https://i0.hdslb.com/'));
      expect(detail.promotion, '指定商品1件3折');
    });

    test('a deposit is shown separately using the verified yuan field', () {
      final detail = MallProductDetail.fromJson(
        _fixture('presale_detail')['data'] as Map<String, dynamic>,
      );
      expect(detail.product.priceText, '商品价¥115');
      expect(detail.product.priceFen, 11500);
      expect(detail.properties['定金'], '¥17.25（非全款）');
      expect(detail.depositFen, 1725);
      expect(detail.deliveryEstimate, '2027年04月');
      expect(detail.properties['预计发货'], '2027年04月');
    });

    test('decimal money parsing never rounds a floating point product', () {
      expect(mallYuanToFen(10.35), 1035);
      expect(mallYuanToFen('0.29'), 29);
      expect(mallYuanToFen('128.70'), 12870);
      expect(mallYuanToFen('0'), 0);
      for (final value in ['1.234', '-1', 'NaN', 'Infinity', '¥3', null]) {
        expect(mallYuanToFen(value), isNull, reason: '$value');
      }
    });

    test(
      'malformed optional rows are skipped without discarding good items',
      () {
        final data = _fixture('search')['data'] as Map<String, dynamic>;
        final first = (data['list'] as List).first;
        final page = MallPage.fromSearch(
          {
            ...data,
            'list': [
              null,
              const {'itemsId': 12},
              first,
              first,
            ],
          },
          requestedPage: 2,
        );
        expect(page.items, hasLength(1));
        expect(page.page, 2);
        expect(
          () => MallPage.fromSearch({
            ...data,
            'list': const [{}],
          }, requestedPage: 1),
          throwsFormatException,
        );
      },
    );

    test(
      'untrusted links and active HTML are not exposed to the native view',
      () {
        expect(
          mallOfficialUrl('https://mall.bilibili.com.evil.test/item'),
          isNull,
        );
        expect(mallOfficialUrl('https://user@mall.bilibili.com/item'), isNull);
        expect(mallOfficialUrl('javascript:alert(1)'), isNull);
        expect(mallImageUrl('https://i0.hdslb.com.evil.test/a.png'), isNull);
        expect(mallImageUrl('data:image/svg+xml,x'), isNull);
        final detail = MallProductDetail.fromJson(const {
          'itemsId': 1,
          'name': '公开商品',
          'price': '1',
          'mobileDesc':
              '<p>商品介绍</p><script>secret()</script>'
              '<img src="javascript:alert(1)">'
              '<img src="//i0.hdslb.com/verified.jpg">',
        });
        expect(detail.description, '商品介绍');
        expect(detail.descriptionImages, ['https://i0.hdslb.com/verified.jpg']);
      },
    );
  });

  group('native mall HTTP client', () {
    late Dio client;
    late MallHttp mall;

    setUp(() {
      client = Dio();
      mall = MallHttp(client: client);
    });

    tearDown(() => client.close(force: true));

    test(
      'home loads the real feed and categories, then reuses category data',
      () async {
        final adapter = _Adapter(
          (options) => _json(
            _fixture(
              options.path.endsWith('/feed/list') ? 'feed' : 'new_items',
            ),
          ),
        );
        client.httpClientAdapter = adapter;

        final first = await mall.home();
        expect(first, isA<Success<MallPage>>());
        expect(first.data.items, hasLength(12));
        expect(first.data.categories, hasLength(11));
        expect(adapter.requests, hasLength(2));
        for (final request in adapter.requests) {
          expect(request.uri.scheme, 'https');
          expect(request.uri.host, 'mall.bilibili.com');
          expect(request.followRedirects, isFalse);
          expect(request.headers['cookie'], isNull);
          expect(request.headers['authorization'], isNull);
        }

        await mall.home(page: 2);
        expect(adapter.requests, hasLength(3));
        expect(adapter.requests.last.queryParameters['pageNum'], 2);
        expect(adapter.requests.last.queryParameters['pageSize'], 10);
      },
    );

    test(
      'category browsing passes the category ID returned by the catalog',
      () async {
        final adapter = _Adapter((_) => _json(_fixture('new_items')));
        client.httpClientAdapter = adapter;
        final result = await mall.home(categoryId: 1, page: 2);
        expect(result, isA<Success<MallPage>>());
        expect(adapter.requests.single.queryParameters['cateType'], 1);
        expect(adapter.requests.single.queryParameters['pageNum'], 2);
      },
    );

    test(
      'search posts the observed read-only query and keeps its requested page',
      () async {
        final adapter = _Adapter((_) => _json(_fixture('search')));
        client.httpClientAdapter = adapter;
        final result = await mall.search(' 初音未来 ', page: 2);
        expect(result, isA<Success<MallPage>>());
        expect(result.data.page, 2);
        final request = adapter.requests.single;
        expect(request.method, 'POST');
        expect(request.uri.path, '/mall/noah/search/category/v2');
        expect(request.data['keyword'], '初音未来');
        expect(request.data['pageIndex'], 2);
        expect(request.data['userId'], '');
      },
    );

    test(
      'search serializes exact yuan bounds into official rangeQueries',
      () async {
        final adapter = _Adapter((_) => _json(_fixture('search')));
        client.httpClientAdapter = adapter;
        await mall.search(
          '手办',
          page: 2,
          options: const MallSearchOptions(
            sort: MallSort.priceAscending,
            minimumFen: 29,
            maximumFen: 10000,
          ),
        );
        final body = adapter.requests.single.data;
        expect(body['sortType'], 'price');
        expect(body['sortOrder'], 'asc');
        expect(body['rangeQueries'], [
          {'field': 'price', 'gte': '0.29', 'lte': '100.00'},
        ]);
        expect(body['userId'], '');
        expect(body['pageIndex'], 2);
        expect(adapter.requests.single.headers['cookie'], isNull);
      },
    );

    test(
      'unsupported price ranges fail locally without a network request',
      () async {
        final adapter = _Adapter((_) => _json(_fixture('search')));
        client.httpClientAdapter = adapter;
        for (final options in [
          const MallSearchOptions(minimumFen: -1),
          const MallSearchOptions(minimumFen: 100, maximumFen: 99),
          const MallSearchOptions(maximumFen: 100000000001),
        ]) {
          expect(await mall.search('手办', options: options), isA<MallFailure>());
        }
        expect(adapter.requests, isEmpty);
      },
    );

    test(
      'sales, newest and descending sorts retain official API values',
      () async {
        final adapter = _Adapter((_) => _json(_fixture('search')));
        client.httpClientAdapter = adapter;
        for (final (sort, type, order) in [
          (MallSort.sales, 'sale', ''),
          (MallSort.newest, 'pubdate', ''),
          (MallSort.priceDescending, 'price', 'desc'),
        ]) {
          await mall.search(
            '手办',
            options: MallSearchOptions(sort: sort, maximumFen: 10000),
          );
          expect(adapter.requests.last.data['sortType'], type);
          expect(adapter.requests.last.data['sortOrder'], order);
          expect(adapter.requests.last.data['rangeQueries'], [
            {'field': 'price', 'gte': '', 'lte': '100.00'},
          ]);
        }
      },
    );

    test(
      'detail rejects a response belonging to a different product',
      () async {
        client.httpClientAdapter = _Adapter((_) => _json(_fixture('detail')));
        final good = await mall.detail('11092663');
        expect(good, isA<Success<MallProductDetail>>());
        final wrong = await mall.detail('42547033');
        expect(wrong, isA<MallFailure>());
        expect((wrong as MallFailure).kind, MallFailureKind.invalidResponse);
      },
    );

    for (final (code, kind) in [
      (-101, MallFailureKind.authentication),
      (-412, MallFailureKind.rateLimited),
      (81102001, MallFailureKind.unavailable),
    ]) {
      test('API code $code produces a useful typed failure', () async {
        client.httpClientAdapter = _Adapter(
          (_) => _json({'code': code, 'message': '暂不可用'}),
        );
        final result = await mall.search('手办');
        expect(result, isA<MallFailure>());
        expect((result as MallFailure).kind, kind);
      });
    }

    for (final (status, kind) in [
      (401, MallFailureKind.authentication),
      (429, MallFailureKind.rateLimited),
      (503, MallFailureKind.unavailable),
      (302, MallFailureKind.unavailable),
    ]) {
      test('HTTP $status never becomes an empty successful catalog', () async {
        client.httpClientAdapter = _Adapter(
          (_) => _json({}, status: status),
        );
        final result = await mall.search('手办');
        expect(result, isA<MallFailure>());
        expect((result as MallFailure).kind, kind);
      });
    }

    test(
      'network failures and malformed data remain distinguishable',
      () async {
        client.httpClientAdapter = _Adapter(
          (options) => throw DioException.connectionError(
            requestOptions: options,
            reason: 'offline',
          ),
        );
        var result = await mall.search('手办');
        expect((result as MallFailure).kind, MallFailureKind.network);
        client.httpClientAdapter = _Adapter(
          (_) => _json({'code': 0, 'data': {}}),
        );
        result = await mall.search('手办');
        expect((result as MallFailure).kind, MallFailureKind.invalidResponse);
      },
    );

    test(
      'cancellation propagates to an in-flight request without a toast',
      () async {
        final started = Completer<void>();
        final response = Completer<ResponseBody>();
        client.httpClientAdapter = _Adapter((_) {
          started.complete();
          return response.future;
        });
        final cancel = CancelToken();
        final pending = mall.search('手办', cancelToken: cancel);
        await started.future;
        cancel.cancel();
        final result = await pending.timeout(const Duration(seconds: 2));
        response.complete(_json(_fixture('search')));
        expect((result as MallFailure).kind, MallFailureKind.cancelled);
      },
    );

    test('an injected client remains owned by its caller', () {
      final adapter = _Adapter((_) => _json(_fixture('search')));
      client.httpClientAdapter = adapter;
      mall.close();
      expect(adapter.closed, isFalse);
    });
  });
}
