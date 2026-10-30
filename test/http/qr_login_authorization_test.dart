import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/http/qr_login_authorization.dart';
import 'package:PiliPlus/models/qr_login_authorization.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = '0123456789abcdef0123456789abcdef';

QrLoginAuthorizationRequest _request({
  bool tv = false,
  DateTime? now,
}) => QrLoginAuthorizationRequest.parse(
  tv
      ? 'https://passport.bilibili.com/x/passport-tv-login/h5/qrcode/auth?auth_code=$_key&mobi_app=android_hd'
      : 'https://account.bilibili.com/h5/account-h5/auth/scan-web?qrcode_key=$_key',
  now: now,
)!;

LoginAccount _account([int mid = 123]) => LoginAccount(
  BiliCookieJar.fromJson({
    'SESSDATA': 'session-$mid',
    'bili_jct': 'csrf-$mid',
    'DedeUserID': '$mid',
  }),
  null,
  null,
  null,
  'test-buvid',
);

ResponseBody _json(Object value, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    'content-type': ['application/json'],
  },
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  final bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = BytesBuilder();
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.add(chunk);
      }
    }
    bodies.add(utf8.decode(bytes.takeBytes()));
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

class _Repository extends QrLoginAuthorizationRepository {
  int preparationCount = 0;
  int authorizationCount = 0;
  QrLoginAuthorizationScene scene = const QrLoginAuthorizationScene(
    differentLocation: false,
    location: '测试地点',
  );
  Completer<QrLoginAuthorizationScene>? pendingPreparation;
  Completer<void>? pendingAuthorization;
  QrLoginAuthorizationFailure? authorizationFailure;
  bool? lastTemporary;

  @override
  Future<QrLoginAuthorizationScene> prepare(
    QrLoginAuthorizationRequest request,
    Account account, {
    required bool Function() isCurrent,
    required CancelToken cancelToken,
  }) async {
    preparationCount++;
    return pendingPreparation?.future ?? scene;
  }

  @override
  Future<void> authorize(
    QrLoginAuthorizationRequest request,
    Account account, {
    required bool Function() isCurrent,
    required CancelToken cancelToken,
    bool temporary = false,
  }) async {
    authorizationCount++;
    lastTemporary = temporary;
    if (authorizationFailure case final error?) throw error;
    await pendingAuthorization?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'web preflight only reads, confirmation uses bound cookies and form CSRF',
    () async {
      final adapter = _Adapter(
        (request) => _json({
          'code': 0,
          'data': request.path.endsWith('/scene')
              ? {'location_diff': 1, 'qrcode_location': '测试地点'}
              : {'gourl': 'https://evil.test/do-not-open'},
        }),
      );
      final repository = BilibiliQrLoginAuthorizationRepository(
        adapter: adapter,
      );
      addTearDown(repository.close);
      final account = _account();
      final request = _request();
      final scene = await repository.prepare(
        request,
        account,
        isCurrent: () => true,
        cancelToken: CancelToken(),
      );
      expect(scene.differentLocation, isTrue);
      expect(scene.location, '测试地点');
      expect(adapter.requests.map((request) => request.method), ['GET', 'GET']);
      expect(
        adapter.requests.first.uri.queryParameters.containsKey('csrf'),
        isFalse,
      );
      await repository.authorize(
        request,
        account,
        isCurrent: () => true,
        cancelToken: CancelToken(),
      );
      expect(adapter.requests, hasLength(3));
      final sent = adapter.requests.last;
      expect(sent.uri.host, 'passport.bilibili.com');
      expect(sent.uri.path, '/x/passport-login/web/qrcode/confirm');
      expect(sent.uri.hasQuery, isFalse);
      expect(sent.method, 'POST');
      expect(sent.followRedirects, isFalse);
      expect(sent.maxRedirects, 0);
      expect(sent.headers['cookie'], contains('SESSDATA=session-123'));
      expect(Uri.splitQueryString(adapter.bodies.last), {
        'qrcode_key': _key,
        'buvid': 'test-buvid',
        'transient': 'false',
        'env_key': '',
        'verify_type': '',
        'verify_code': '',
        'verify_key': '',
        'csrf': 'csrf-123',
      });
    },
  );

  test('TV uses its fixed scene and confirmation endpoints', () async {
    final adapter = _Adapter(
      (request) => _json({
        'code': 0,
        'data': {'location_diff': 0, 'qrcode_location': ''},
      }),
    );
    final repository = BilibiliQrLoginAuthorizationRepository(adapter: adapter);
    addTearDown(repository.close);
    final account = _account();
    final request = _request(tv: true);
    await repository.prepare(
      request,
      account,
      isCurrent: () => true,
      cancelToken: CancelToken(),
    );
    await repository.authorize(
      request,
      account,
      isCurrent: () => true,
      cancelToken: CancelToken(),
    );
    expect(adapter.requests, hasLength(2));
    expect(
      adapter.requests.first.uri.path,
      '/x/passport-tv-login/h5/qrcode/scene',
    );
    expect(
      adapter.requests.last.uri.path,
      '/x/passport-tv-login/h5/qrcode/confirm',
    );
    expect(Uri.splitQueryString(adapter.bodies.last), {
      'auth_code': _key,
      'mobi_app': 'android_hd',
      'scanning_type': '1',
      'csrf': 'csrf-123',
    });
  });

  for (final failure in ['timeout', 'redirect']) {
    test(
      'confirmation $failure is uncertain and is never automatically repeated',
      () async {
        final adapter = _Adapter((request) {
          if (failure == 'timeout') {
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.connectionTimeout,
            );
          }
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['https://passport.bilibili.com/another-endpoint'],
            },
          );
        });
        final repository = BilibiliQrLoginAuthorizationRepository(
          adapter: adapter,
        );
        addTearDown(repository.close);
        await expectLater(
          repository.authorize(
            _request(),
            _account(),
            isCurrent: () => true,
            cancelToken: CancelToken(),
          ),
          throwsA(
            isA<QrLoginAuthorizationFailure>().having(
              (failure) => failure.kind,
              'kind',
              QrLoginAuthorizationFailureKind.uncertain,
            ),
          ),
        );
        expect(adapter.requests, hasLength(1));
      },
    );
  }

  test('expired and switched accounts never send authorization', () async {
    final adapter = _Adapter((request) => _json({'code': 0}));
    final repository = BilibiliQrLoginAuthorizationRepository(adapter: adapter);
    addTearDown(repository.close);
    for (final changed in [false, true]) {
      await expectLater(
        repository.authorize(
          _request(now: DateTime.now().subtract(const Duration(minutes: 4))),
          _account(),
          isCurrent: () => !changed,
          cancelToken: CancelToken(),
        ),
        throwsA(isA<QrLoginAuthorizationFailure>()),
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test('official expiry response is surfaced without confirmation', () async {
    final adapter = _Adapter((request) => _json({'code': 86038}));
    final repository = BilibiliQrLoginAuthorizationRepository(adapter: adapter);
    addTearDown(repository.close);
    await expectLater(
      repository.prepare(
        _request(),
        _account(),
        isCurrent: () => true,
        cancelToken: CancelToken(),
      ),
      throwsA(
        isA<QrLoginAuthorizationFailure>().having(
          (failure) => failure.kind,
          'kind',
          QrLoginAuthorizationFailureKind.expired,
        ),
      ),
    );
    expect(adapter.requests.map((request) => request.method), ['GET']);
  });

  for (final gate in ['verify_tel', 'obtain_env']) {
    for (final value in [1, true, '1']) {
      test(
        'unimplemented official $gate verification rejects $value',
        () async {
          final adapter = _Adapter(
            (_) => _json({
              'code': 0,
              'data': {
                'location_diff': 0,
                'qrcode_location': '',
                gate: value,
              },
            }),
          );
          final repository = BilibiliQrLoginAuthorizationRepository(
            adapter: adapter,
          );
          final account = _account();
          final session = QrLoginAuthorizationSession(
            request: _request(),
            repository: repository,
            currentAccount: () => account,
          );
          addTearDown(session.dispose);
          await session.prepare();
          expect(session.phase, QrLoginAuthorizationPhase.failed);
          expect(
            session.failure?.kind,
            QrLoginAuthorizationFailureKind.officialVerificationRequired,
          );
          await session.authorize();
          expect(adapter.requests.map((request) => request.method), [
            'GET',
            'GET',
          ]);
        },
      );
    }
  }

  test('scene labels are cleaned and temporary login stays optional', () async {
    final adapter = _Adapter(
      (_) => _json({
        'code': 0,
        'data': {
          'location_diff': false,
          'qrcode_location': ' \u202e地点\n ',
          'app': {'title': ' \u202e官方应用\n '},
          'transient': 1,
          'verify_tel': 0,
          'obtain_env': false,
        },
      }),
    );
    final repository = BilibiliQrLoginAuthorizationRepository(adapter: adapter);
    addTearDown(repository.close);
    final account = _account();
    final request = _request();
    final scene = await repository.prepare(
      request,
      account,
      isCurrent: () => true,
      cancelToken: CancelToken(),
    );
    expect(scene.location, '地点');
    expect(scene.application, '官方应用');
    expect(scene.supportsTemporary, isTrue);
    expect(
      adapter.requests.every((request) => request.method == 'GET'),
      isTrue,
    );
    await repository.authorize(
      request,
      account,
      isCurrent: () => true,
      cancelToken: CancelToken(),
      temporary: true,
    );
    expect(Uri.splitQueryString(adapter.bodies.last)['transient'], 'true');
  });

  test(
    'scene labels are bounded and TV never offers web temporary login',
    () async {
      final adapter = _Adapter(
        (_) => _json({
          'code': 0,
          'data': {
            'location_diff': 0,
            'qrcode_location': '地' * 200,
            'app': {'title': '名' * 200},
            'transient': true,
          },
        }),
      );
      final repository = BilibiliQrLoginAuthorizationRepository(
        adapter: adapter,
      );
      addTearDown(repository.close);
      final scene = await repository.prepare(
        _request(tv: true),
        _account(),
        isCurrent: () => true,
        cancelToken: CancelToken(),
      );
      expect(scene.location.length, 120);
      expect(scene.application.length, 100);
      expect(scene.supportsTemporary, isFalse);
    },
  );

  test('malformed official scene data cannot enable confirmation', () async {
    final adapter = _Adapter(
      (_) => _json({
        'code': 0,
        'data': {'location_diff': 'false', 'qrcode_location': []},
      }),
    );
    final repository = BilibiliQrLoginAuthorizationRepository(adapter: adapter);
    addTearDown(repository.close);
    await expectLater(
      repository.prepare(
        _request(),
        _account(),
        isCurrent: () => true,
        cancelToken: CancelToken(),
      ),
      throwsA(
        isA<QrLoginAuthorizationFailure>().having(
          (error) => error.kind,
          'kind',
          QrLoginAuthorizationFailureKind.unavailable,
        ),
      ),
    );
    expect(
      adapter.requests.every((request) => request.method == 'GET'),
      isTrue,
    );
  });

  test(
    'account changes while a response is pending invalidate that response',
    () async {
      var current = true;
      final adapter = _Adapter((_) {
        current = false;
        return _json({'code': 0});
      });
      final repository = BilibiliQrLoginAuthorizationRepository(
        adapter: adapter,
      );
      addTearDown(repository.close);
      await expectLater(
        repository.authorize(
          _request(),
          _account(),
          isCurrent: () => current,
          cancelToken: CancelToken(),
        ),
        throwsA(
          isA<QrLoginAuthorizationFailure>().having(
            (error) => error.kind,
            'kind',
            QrLoginAuthorizationFailureKind.accountChanged,
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
    },
  );

  test('cancel before confirmation performs no authorization', () async {
    final repository = _Repository();
    final account = _account();
    final session = QrLoginAuthorizationSession(
      request: _request(),
      repository: repository,
      currentAccount: () => account,
    );
    addTearDown(session.dispose);
    await session.prepare();
    session.cancel();
    await session.authorize();
    expect(repository.authorizationCount, 0);
    expect(session.phase, QrLoginAuthorizationPhase.cancelled);
  });

  test(
    'double taps and repeated calls submit at most one authorization',
    () async {
      final repository = _Repository()
        ..pendingAuthorization = Completer<void>();
      final account = _account();
      final session = QrLoginAuthorizationSession(
        request: _request(),
        repository: repository,
        currentAccount: () => account,
      );
      addTearDown(session.dispose);
      await session.prepare();
      final first = session.authorize();
      await session.authorize();
      expect(repository.authorizationCount, 1);
      repository.pendingAuthorization!.complete();
      await first;
      await session.authorize();
      expect(repository.authorizationCount, 1);
      expect(session.phase, QrLoginAuthorizationPhase.completed);
    },
  );

  test(
    'account change invalidates a pending result and cannot submit again',
    () async {
      final repository = _Repository()
        ..pendingAuthorization = Completer<void>();
      Account account = _account();
      final session = QrLoginAuthorizationSession(
        request: _request(),
        repository: repository,
        currentAccount: () => account,
      );
      addTearDown(session.dispose);
      await session.prepare();
      final pending = session.authorize();
      account = _account(456);
      session.checkContext();
      repository.pendingAuthorization!.complete();
      await pending;
      expect(session.phase, QrLoginAuthorizationPhase.failed);
      expect(
        session.failure?.kind,
        QrLoginAuthorizationFailureKind.accountChanged,
      );
      await session.authorize();
      expect(repository.authorizationCount, 1);
    },
  );

  test('expired challenges cannot be confirmed', () async {
    final repository = _Repository();
    final account = _account();
    final session = QrLoginAuthorizationSession(
      request: _request(
        now: DateTime.now().subtract(const Duration(minutes: 4)),
      ),
      repository: repository,
      currentAccount: () => account,
    );
    addTearDown(session.dispose);
    await session.prepare();
    await session.authorize();
    expect(session.failure?.kind, QrLoginAuthorizationFailureKind.expired);
    expect(repository.authorizationCount, 0);
    expect(repository.preparationCount, 0);
  });

  for (final duringPreparation in [true, false]) {
    test(
      'late success cannot revive a failed session, preparing=$duringPreparation',
      () async {
        final repository = _Repository();
        final original = _account();
        Account current = original;
        final session = QrLoginAuthorizationSession(
          request: _request(),
          repository: repository,
          currentAccount: () => current,
        );
        addTearDown(session.dispose);
        late final Future<void> pending;
        if (duringPreparation) {
          repository.pendingPreparation =
              Completer<QrLoginAuthorizationScene>();
          pending = session.prepare();
        } else {
          await session.prepare();
          repository.pendingAuthorization = Completer<void>();
          pending = session.authorize();
        }
        current = _account(456);
        session.checkContext();
        current = original;
        if (duringPreparation) {
          repository.pendingPreparation!.complete(repository.scene);
        } else {
          repository.pendingAuthorization!.complete();
        }
        await pending;
        expect(session.phase, QrLoginAuthorizationPhase.failed);
        expect(
          session.failure?.kind,
          QrLoginAuthorizationFailureKind.accountChanged,
        );
        expect(session.canAuthorize, isFalse);
      },
    );
  }

  test(
    'cancelled preparation cannot become ready after its response arrives',
    () async {
      final repository = _Repository()
        ..pendingPreparation = Completer<QrLoginAuthorizationScene>();
      final account = _account();
      final session = QrLoginAuthorizationSession(
        request: _request(),
        repository: repository,
        currentAccount: () => account,
      );
      addTearDown(session.dispose);
      final pending = session.prepare();
      session.cancel();
      repository.pendingPreparation!.complete(repository.scene);
      await pending;
      expect(session.phase, QrLoginAuthorizationPhase.cancelled);
      expect(repository.authorizationCount, 0);
    },
  );

  test(
    'an uncertain confirmation cannot be repeated from the session',
    () async {
      final repository = _Repository()
        ..authorizationFailure = const QrLoginAuthorizationFailure(.uncertain);
      final account = _account();
      final session = QrLoginAuthorizationSession(
        request: _request(),
        repository: repository,
        currentAccount: () => account,
      );
      addTearDown(session.dispose);
      await session.prepare();
      await session.authorize();
      await session.authorize();
      expect(session.failure?.kind, QrLoginAuthorizationFailureKind.uncertain);
      expect(repository.authorizationCount, 1);
    },
  );

  for (final supported in [false, true]) {
    test(
      'temporary login can only be enabled by the official scene: $supported',
      () async {
        final repository = _Repository()
          ..scene = QrLoginAuthorizationScene(
            differentLocation: false,
            location: '',
            supportsTemporary: supported,
          );
        final account = _account();
        final session = QrLoginAuthorizationSession(
          request: _request(),
          repository: repository,
          currentAccount: () => account,
        );
        addTearDown(session.dispose);
        await session.prepare();
        await session.authorize(temporary: true);
        expect(repository.lastTemporary, supported);
      },
    );
  }

  test(
    'unsigned users must log in and rescan before any network access',
    () async {
      final repository = _Repository();
      final session = QrLoginAuthorizationSession(
        request: _request(),
        repository: repository,
        currentAccount: AnonymousAccount.new,
      );
      addTearDown(session.dispose);
      await session.prepare();
      expect(repository.preparationCount, 0);
      expect(
        session.failure?.kind,
        QrLoginAuthorizationFailureKind.loginRequired,
      );
    },
  );
}
