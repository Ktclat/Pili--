import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/mall/mall.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

enum MallFailureKind {
  network,
  authentication,
  rateLimited,
  cancelled,
  invalidResponse,
  unavailable,
}

class MallFailure extends Error {
  final MallFailureKind kind;

  const MallFailure(this.kind, String message, {super.code}) : super(message);
}

abstract interface class MallRepository {
  Future<LoadingState<MallPage>> home({
    int page = 1,
    int categoryId = 0,
    CancelToken? cancelToken,
  });

  Future<LoadingState<MallPage>> search(
    String query, {
    int page = 1,
    CancelToken? cancelToken,
  });

  Future<LoadingState<MallProductDetail>> detail(
    String id, {
    CancelToken? cancelToken,
  });
}

/// Read-only endpoints observed in the official mall web client. This client
/// deliberately has no account/cookie interceptor and never submits an order.
class MallHttp implements MallRepository {
  static const _host = 'https://mall.bilibili.com';
  static const _feedPageSize = 10;
  static const _searchPageSize = 20;
  static const _newItemsReferer =
      '$_host/newdate.html?noTitleBar=1&page=new&from=new_product&loadingShow=1';

  final Dio _client;
  final bool _ownsClient;
  List<MallCategory> _categories = const [];

  MallHttp({Dio? client})
    : _ownsClient = client == null,
      _client = client ?? _createClient();

  static Dio _createClient() {
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: {'user-agent': BrowserUa.mob, 'accept': 'application/json'},
      ),
    );
    final useProxy = Pref.enableSystemProxy;
    final host = useProxy ? Pref.systemProxyHost : '';
    final port = useProxy ? int.tryParse(Pref.systemProxyPort) : null;
    client.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final http = HttpClient()..idleTimeout = const Duration(seconds: 15);
        if (host.isNotEmpty && port != null && port > 0 && port <= 65535) {
          http.findProxy = (_) => 'PROXY $host:$port';
        }
        return http;
      },
    );
    return client;
  }

  void close() {
    if (_ownsClient) _client.close(force: true);
  }

  @override
  Future<LoadingState<MallPage>> home({
    int page = 1,
    int categoryId = 0,
    CancelToken? cancelToken,
  }) async {
    if (page < 1 || categoryId < 0) {
      return const MallFailure(MallFailureKind.unavailable, '无效的商品分页');
    }
    if (categoryId != 0) {
      final result = await _newItems(
        page: page,
        categoryId: categoryId,
        cancelToken: cancelToken,
      );
      if (result case Success<MallPage>(:final response)) {
        if (response.categories.isNotEmpty) _categories = response.categories;
      }
      return result;
    }

    // Fetch the verified category catalog once; recommendation pages themselves
    // have no category definitions. Both public requests share cancellation.
    final categories = _categories.isEmpty
        ? _newItems(page: 1, categoryId: 0, cancelToken: cancelToken)
        : null;
    final feed = await _request<MallPage>(
      '/mall-c-search/home/feed/list',
      query: {
        'network': '',
        'mobi_app': 'android',
        'openEvent': 'cold',
        'build': 0,
        'pageNum': page,
        'pageSize': _feedPageSize,
        'mVersion': 7,
        'platform': 'h5',
        'mobiApp': 'android',
        'feedType': 0,
      },
      cancelToken: cancelToken,
      parse: (data) => MallPage.fromFeed(
        _vo(data),
        requestedPage: page,
        pageSize: _feedPageSize,
      ),
    );
    if (categories != null) {
      final result = await categories;
      if (result case Success<MallPage>(:final response)) {
        _categories = response.categories;
      }
    }
    if (cancelToken?.isCancelled == true) return _cancelled;
    if (feed case Success<MallPage>(:final response)) {
      return Success(
        MallPage(
          items: response.items,
          categories: _categories,
          page: response.page,
          total: response.total,
          hasNext: response.hasNext,
        ),
      );
    }
    return feed;
  }

  Future<LoadingState<MallPage>> _newItems({
    required int page,
    required int categoryId,
    CancelToken? cancelToken,
  }) => _request(
    '/mall-c-search/home/new_items/list',
    query: {
      'pageNum': page,
      'pageSize': _searchPageSize,
      'version': '1.0',
      'cityId': 0,
      'cateType': categoryId,
    },
    referer: _newItemsReferer,
    cancelToken: cancelToken,
    parse: (data) => MallPage.fromNewItems(_vo(data)),
  );

  @override
  Future<LoadingState<MallPage>> search(
    String query, {
    int page = 1,
    CancelToken? cancelToken,
  }) {
    final keyword = query.trim();
    if (keyword.isEmpty || keyword.length > 200 || page < 1) {
      return Future.value(
        const MallFailure(MallFailureKind.unavailable, '请输入有效的搜索词'),
      );
    }
    return _request(
      '/mall/noah/search/category/v2',
      method: 'POST',
      body: {
        'keyword': keyword,
        'filters': '',
        'priceFlow': '',
        'priceCeil': '',
        'sortType': 'totalrank',
        'sortOrder': '',
        'pageIndex': page,
        'pageSize': _searchPageSize,
        'userId': '',
        'state': '',
        'termQueries': [
          {
            'field': 'sold_status',
            'values': ['1'],
          },
        ],
        'rangeQueries': <Object>[],
      },
      cancelToken: cancelToken,
      parse: (data) => MallPage.fromSearch(data, requestedPage: page),
    );
  }

  @override
  Future<LoadingState<MallProductDetail>> detail(
    String id, {
    CancelToken? cancelToken,
  }) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(id)) {
      return Future.value(
        const MallFailure(MallFailureKind.unavailable, '无效的商品编号'),
      );
    }
    return _request(
      '/mall-search-items/items/merchant/info',
      query: {
        'itemsId': id,
        'shopId': '',
        'itemsVersion': '',
        'from': 'new_product',
        'themeMode': 1,
      },
      referer:
          '$_host/neul-next/detailuniversal/detail.html'
          '?page=detailuniversal_detail&itemsId=$id',
      cancelToken: cancelToken,
      parse: (data) {
        final detail = MallProductDetail.fromJson(data);
        if (detail.product.id != id) {
          throw const FormatException('Product identity mismatch');
        }
        return detail;
      },
    );
  }

  static Map<String, dynamic> _vo(Map<String, dynamic> data) {
    final vo = mallMap(data['vo']);
    if (vo == null) throw const FormatException('Missing mall result');
    return vo;
  }

  static const _cancelled = MallFailure(MallFailureKind.cancelled, '请求已取消');

  Future<LoadingState<T>> _request<T>(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? query,
    Object? body,
    String referer = '$_host/',
    CancelToken? cancelToken,
    required T Function(Map<String, dynamic>) parse,
  }) async {
    if (cancelToken?.isCancelled == true) return _cancelled;
    try {
      final response = await _client.request<Object?>(
        '$_host$path',
        queryParameters: query,
        data: body,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          followRedirects: false,
          responseType: ResponseType.json,
          contentType: Headers.jsonContentType,
          headers: {'referer': referer},
          validateStatus: (status) =>
              status != null && status >= 200 && status < 600,
        ),
      );
      if (cancelToken?.isCancelled == true) return _cancelled;
      final status = response.statusCode ?? 0;
      if (status == 401) {
        return const MallFailure(
          MallFailureKind.authentication,
          '官方接口需要登录授权，请在官方客户端查看',
          code: 401,
        );
      }
      if (status == 429) {
        return const MallFailure(
          MallFailureKind.rateLimited,
          '请求过于频繁，请稍后重试',
          code: 429,
        );
      }
      if (status < 200 || status >= 300) {
        return MallFailure(
          MallFailureKind.unavailable,
          '会员购服务暂不可用，请稍后重试',
          code: status,
        );
      }
      final raw = response.data;
      final root = mallMap(raw is String ? jsonDecode(raw) : raw);
      final code = mallInt(root?['code']);
      if (root == null || code == null) {
        throw const FormatException('Missing mall API status');
      }
      final data = mallMap(root['data']);
      if (code != 0 ||
          root['success'] == false ||
          (data?['codeType'] != null && mallInt(data?['codeType']) != 1)) {
        final message = mallText(data?['codeMsg']) ?? mallText(root['message']);
        if (code == -101 || code == -102) {
          return MallFailure(
            MallFailureKind.authentication,
            '官方接口需要登录授权，请在官方客户端查看',
            code: code,
          );
        }
        if (code == -412 || code == -509 || code == 429) {
          return MallFailure(
            MallFailureKind.rateLimited,
            '请求受限，请稍后重试',
            code: code,
          );
        }
        return MallFailure(
          MallFailureKind.unavailable,
          message ?? '商品暂不可用，请稍后重试',
          code: code,
        );
      }
      if (data == null) throw const FormatException('Missing mall API data');
      return Success(parse(data));
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || cancelToken?.isCancelled == true) {
        return _cancelled;
      }
      return const MallFailure(
        MallFailureKind.network,
        '无法连接会员购，请检查网络后重试',
      );
    } on FormatException {
      return const MallFailure(
        MallFailureKind.invalidResponse,
        '商品数据格式已变化，请稍后重试',
      );
    } on TypeError {
      return const MallFailure(
        MallFailureKind.invalidResponse,
        '商品数据不完整，请稍后重试',
      );
    }
  }
}
