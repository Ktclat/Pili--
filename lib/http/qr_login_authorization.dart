import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/models/qr_login_authorization.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

abstract class QrLoginAuthorizationRepository {
  Future<QrLoginAuthorizationScene> prepare(
    QrLoginAuthorizationRequest request,
    Account account, {
    required bool Function() isCurrent,
    required CancelToken cancelToken,
  });

  Future<void> authorize(
    QrLoginAuthorizationRequest request,
    Account account, {
    required bool Function() isCurrent,
    required CancelToken cancelToken,
    bool temporary = false,
  });

  void close() {}
}

/// Official account-h5 and passport-h5 scan contracts. This dedicated client has no
/// retry, redirect, analytics, logging, or global account mutation interceptors.
class BilibiliQrLoginAuthorizationRepository
    implements QrLoginAuthorizationRepository {
  BilibiliQrLoginAuthorizationRepository({HttpClientAdapter? adapter})
    : _client = Dio(
        BaseOptions(
          baseUrl: 'https://passport.bilibili.com',
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          followRedirects: false,
          maxRedirects: 0,
          headers: {
            'user-agent': BrowserUa.mob,
            'origin': 'https://passport.bilibili.com',
            'referer': 'https://passport.bilibili.com/',
          },
        ),
      ) {
    if (adapter != null) _client.httpClientAdapter = adapter;
  }

  final Dio _client;

  static const _webRoot = '/x/passport-login/web/qrcode';
  static const _tvRoot = '/x/passport-tv-login/h5/qrcode';

  @override
  Future<QrLoginAuthorizationScene> prepare(
    QrLoginAuthorizationRequest request,
    Account account, {
    required bool Function() isCurrent,
    required CancelToken cancelToken,
  }) async {
    final query = {
      request.kind == .web ? 'qrcode_key' : 'auth_code': request.token,
      if (request.kind == .web) 'buvid': account.buvid,
    };
    if (request.kind == .web) {
      await _call(
        '$_webRoot/check',
        request,
        account,
        query,
        isCurrent: isCurrent,
        cancelToken: cancelToken,
      );
    }
    final root = request.kind == .web ? _webRoot : _tvRoot;
    final data = await _call(
      '$root/scene',
      request,
      account,
      query,
      isCurrent: isCurrent,
      cancelToken: cancelToken,
    );
    if (data is! Map) {
      throw const QrLoginAuthorizationFailure(.unavailable);
    }
    final different = data['location_diff'];
    final location = data['qrcode_location'];
    if ([data['verify_tel'], data['obtain_env']].any(
      (value) => value != null && value != false && value != 0,
    )) {
      throw const QrLoginAuthorizationFailure(.officialVerificationRequired);
    }
    if ((different is! bool && different != 0 && different != 1) ||
        (location != null && location is! String)) {
      throw const QrLoginAuthorizationFailure(.unavailable);
    }
    return QrLoginAuthorizationScene(
      differentLocation: different == true || different == 1,
      location: _label(location as String? ?? '', 120),
      application: switch (data['app']) {
        {'title': final String title} => _label(title, 100),
        _ => '',
      },
      supportsTemporary:
          request.kind == .web &&
          (data['transient'] == true || data['transient'] == 1),
    );
  }

  static String _label(String value, int limit) {
    final clean = value
        .replaceAll(RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]'), '')
        .trim();
    return clean.length > limit ? clean.substring(0, limit) : clean;
  }

  @override
  Future<void> authorize(
    QrLoginAuthorizationRequest request,
    Account account, {
    required bool Function() isCurrent,
    required CancelToken cancelToken,
    bool temporary = false,
  }) async {
    final root = request.kind == .web ? _webRoot : _tvRoot;
    await _call(
      '$root/confirm',
      request,
      account,
      {
        if (request.kind == .web) ...{
          'qrcode_key': request.token,
          'buvid': account.buvid,
          'transient': temporary,
          'env_key': '',
          'verify_type': '',
          'verify_code': '',
          'verify_key': '',
        } else ...{
          'auth_code': request.token,
          ...request.tvParameters,
          'scanning_type': 1,
        },
      },
      isCurrent: isCurrent,
      cancelToken: cancelToken,
      write: true,
    );
  }

  Future<dynamic> _call(
    String path,
    QrLoginAuthorizationRequest request,
    Account account,
    Map<String, dynamic> parameters, {
    required bool Function() isCurrent,
    required CancelToken cancelToken,
    bool write = false,
  }) async {
    void ensureCurrent() {
      if (cancelToken.isCancelled) {
        throw const QrLoginAuthorizationFailure(.cancelled);
      }
      if (!isCurrent()) {
        throw const QrLoginAuthorizationFailure(.accountChanged);
      }
      if (!account.isLogin) {
        throw const QrLoginAuthorizationFailure(.loginRequired);
      }
      if (request.isExpired()) {
        throw const QrLoginAuthorizationFailure(.expired);
      }
    }

    ensureCurrent();
    try {
      final uri = Uri.https('passport.bilibili.com', path);
      final cookies = await account.cookieJar.loadForRequest(uri);
      ensureCurrent();
      if (!cookies.any((cookie) => cookie.name == 'SESSDATA')) {
        throw const QrLoginAuthorizationFailure(.loginRequired);
      }
      final csrf = cookies.where((cookie) => cookie.name == 'bili_jct');
      if (csrf.isEmpty || csrf.first.value.isEmpty) {
        throw const QrLoginAuthorizationFailure(.loginRequired);
      }
      final body = {
        ...parameters,
        if (write) 'csrf': csrf.first.value,
      };
      final options = Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'cookie': cookies
              .map((cookie) => '${cookie.name}=${cookie.value}')
              .join('; '),
          if (request.kind == .web) 'buvid': account.buvid,
        },
      );
      final response = write
          ? await _client.post<dynamic>(
              path,
              data: body,
              options: options,
              cancelToken: cancelToken,
            )
          : await _client.get<dynamic>(
              path,
              queryParameters: body,
              options: options,
              cancelToken: cancelToken,
            );
      if (cancelToken.isCancelled) {
        throw const QrLoginAuthorizationFailure(.cancelled);
      }
      if (!isCurrent()) {
        throw const QrLoginAuthorizationFailure(.accountChanged);
      }
      if (!write && request.isExpired()) {
        throw const QrLoginAuthorizationFailure(.expired);
      }
      final result = response.data;
      if (result is! Map || result['code'] is! num) {
        throw QrLoginAuthorizationFailure(write ? .uncertain : .unavailable);
      }
      final code = result['code'];
      if (code == 86038) {
        throw const QrLoginAuthorizationFailure(.expired);
      }
      if (code == -101) {
        throw const QrLoginAuthorizationFailure(.loginRequired);
      }
      if (code != 0) {
        throw const QrLoginAuthorizationFailure(.rejected);
      }
      // Returned URLs and cookies belong to the remote login flow. Never
      // navigate to them or install them into the current account.
      return result['data'];
    } on QrLoginAuthorizationFailure {
      rethrow;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const QrLoginAuthorizationFailure(.cancelled);
      }
      throw QrLoginAuthorizationFailure(write ? .uncertain : .unavailable);
    } catch (_) {
      throw QrLoginAuthorizationFailure(write ? .uncertain : .unavailable);
    }
  }

  @override
  void close() => _client.close(force: true);
}

enum QrLoginAuthorizationPhase {
  checking,
  ready,
  authorizing,
  completed,
  failed,
  cancelled,
}

/// One scanned challenge, bound to one account, and at most one confirmation.
class QrLoginAuthorizationSession extends ChangeNotifier {
  QrLoginAuthorizationSession({
    required this.request,
    required this.repository,
    Account Function()? currentAccount,
  }) : _currentAccount = currentAccount ?? (() => Accounts.main) {
    account = _currentAccount();
  }

  final QrLoginAuthorizationRequest request;
  final QrLoginAuthorizationRepository repository;
  final Account Function() _currentAccount;
  late final Account account;
  final CancelToken _cancelToken = CancelToken();
  QrLoginAuthorizationPhase phase = .checking;
  QrLoginAuthorizationScene? scene;
  QrLoginAuthorizationFailure? failure;
  bool _disposed = false;
  bool _started = false;
  bool _attempted = false;

  bool get isCurrent =>
      !_disposed &&
      !_cancelToken.isCancelled &&
      identical(account, _currentAccount()) &&
      account.isLogin;
  bool get canAuthorize =>
      phase == .ready && !_attempted && isCurrent && !request.isExpired();

  Future<void> prepare() async {
    if (_started || _disposed || phase == .cancelled) return;
    _started = true;
    if (!account.isLogin) {
      _fail(const QrLoginAuthorizationFailure(.loginRequired));
      return;
    }
    if (request.isExpired()) {
      _fail(const QrLoginAuthorizationFailure(.expired));
      return;
    }
    try {
      scene = await repository.prepare(
        request,
        account,
        isCurrent: () => isCurrent,
        cancelToken: _cancelToken,
      );
      if (_inactive) return;
      if (!isCurrent) {
        _fail(const QrLoginAuthorizationFailure(.accountChanged));
      } else if (request.isExpired()) {
        _fail(const QrLoginAuthorizationFailure(.expired));
      } else {
        phase = .ready;
        notifyListeners();
      }
    } on QrLoginAuthorizationFailure catch (error) {
      _fail(error);
    } catch (_) {
      _fail(const QrLoginAuthorizationFailure(.unavailable));
    }
  }

  Future<void> authorize({bool temporary = false}) async {
    if (_inactive || _attempted || phase != .ready) return;
    if (!isCurrent) {
      _fail(const QrLoginAuthorizationFailure(.accountChanged));
      return;
    }
    if (request.isExpired()) {
      _fail(const QrLoginAuthorizationFailure(.expired));
      return;
    }
    _attempted = true;
    phase = .authorizing;
    notifyListeners();
    try {
      await repository.authorize(
        request,
        account,
        isCurrent: () => isCurrent,
        cancelToken: _cancelToken,
        temporary: temporary && (scene?.supportsTemporary ?? false),
      );
      if (_inactive) return;
      if (!isCurrent) {
        _fail(const QrLoginAuthorizationFailure(.accountChanged));
      } else {
        phase = .completed;
        notifyListeners();
      }
    } on QrLoginAuthorizationFailure catch (error) {
      _fail(error);
    } catch (_) {
      _fail(const QrLoginAuthorizationFailure(.uncertain));
    }
  }

  void checkContext() {
    if (_inactive || phase == .completed || phase == .failed) return;
    if (!identical(account, _currentAccount())) {
      _cancelToken.cancel();
      _fail(const QrLoginAuthorizationFailure(.accountChanged));
    } else if (phase != .authorizing && request.isExpired()) {
      _fail(const QrLoginAuthorizationFailure(.expired));
    }
  }

  bool get _inactive =>
      _disposed ||
      phase == .cancelled ||
      phase == .failed ||
      phase == .completed;

  void _fail(QrLoginAuthorizationFailure error) {
    if (_inactive || phase == .failed || phase == .completed) return;
    phase = .failed;
    failure = error;
    notifyListeners();
  }

  void cancel() {
    if (_inactive || phase == .completed) return;
    phase = .cancelled;
    _cancelToken.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelToken.cancel();
    repository.close();
    super.dispose();
  }
}
