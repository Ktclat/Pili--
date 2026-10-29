import 'dart:async';
import 'dart:typed_data';

import 'package:PiliPlus/http/retry_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http2/http2.dart';

typedef _RecordedRequest = ({
  Uri uri,
  String method,
  Object? data,
  Map<String, dynamic> headers,
});

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions, int) respond;
  final requests = <_RecordedRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add((
      uri: options.uri,
      method: options.method,
      data: options.data,
      headers: Map.of(options.headers),
    ));
    return respond(options, requests.length);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _ok() => ResponseBody.fromString('ok', 200);

ResponseBody _redirect(String target, [int status = 302]) =>
    ResponseBody.fromString(
      '',
      status,
      headers: {
        'location': [target],
      },
    );

void main() {
  late Dio client;

  _Adapter configure(
    FutureOr<ResponseBody> Function(RequestOptions, int) respond, {
    int retries = 2,
  }) {
    final adapter = _Adapter(respond);
    client = Dio(BaseOptions(responseType: ResponseType.plain))
      ..httpClientAdapter = adapter;
    client.interceptors.add(RetryInterceptor(client, retries, 1));
    return adapter;
  }

  tearDown(() => client.close(force: true));

  group('account redirects', () {
    Options accountOptions({String? method}) => Options(
      method: method,
      followRedirects: false,
      extra: {'biliAccountRedirects': true},
      headers: {'cookie': 'SESSDATA=test-session'},
      maxRedirects: 2,
    );

    test(
      'follows a relative same-origin redirect with account headers',
      () async {
        final adapter = configure(
          (_, attempt) =>
              attempt == 1 ? _redirect('../destination?from=redirect') : _ok(),
        );

        final response = await client.get<String>(
          'https://api.bilibili.com/source/start',
          options: accountOptions(),
        );

        expect(response.data, 'ok');
        expect(adapter.requests, hasLength(2));
        expect(
          adapter.requests.last.uri.toString(),
          'https://api.bilibili.com/destination?from=redirect',
        );
        expect(
          adapter.requests.last.headers['cookie'],
          'SESSDATA=test-session',
        );
      },
    );

    for (final target in [
      'https://evil.example/destination',
      '//evil.example/destination',
      'https://www.bilibili.com/destination',
      'http://api.bilibili.com/destination',
      'https://api.bilibili.com:8443/destination',
      'https://user@api.bilibili.com/destination',
      'file:///tmp/destination',
      'javascript:alert(1)',
    ]) {
      test('never sends account data to $target', () async {
        final adapter = configure((_, _) => _redirect(target, 307));

        await expectLater(
          client.post<void>(
            'https://api.bilibili.com/source',
            data: {'csrf': 'test-csrf'},
            options: accountOptions(),
          ),
          throwsA(
            isA<DioException>().having(
              (error) => error.response?.statusCode,
              'status',
              307,
            ),
          ),
        );
        expect(adapter.requests, hasLength(1));
      });
    }

    test('303 changes POST to GET and drops its body', () async {
      final adapter = configure(
        (_, attempt) => attempt == 1 ? _redirect('/result', 303) : _ok(),
      );

      await client.post<void>(
        'https://api.bilibili.com/source',
        data: {'csrf': 'test-csrf'},
        options: accountOptions(),
      );

      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.method, 'POST');
      expect(adapter.requests.last.method, 'GET');
      expect(adapter.requests.last.data, isNull);
    });

    test('stops a same-origin redirect loop at the limit', () async {
      final adapter = configure((_, _) => _redirect('/loop'));

      await expectLater(
        client.get<void>(
          'https://api.bilibili.com/loop',
          options: accountOptions(),
        ),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(3));
    });

    test('does not follow redirects when explicitly disabled', () async {
      final adapter = configure((_, _) => _redirect('/destination'));

      await expectLater(
        client.get<void>(
          'https://example.org/source',
          options: Options(followRedirects: false),
        ),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
    });
  });

  group('network retries', () {
    for (final method in ['GET', 'HEAD']) {
      test(
        '$method retries transient errors and returns the response',
        () async {
          final adapter = configure((options, attempt) {
            if (attempt < 3) {
              throw DioException.connectionError(
                requestOptions: options,
                reason: 'simulated network interruption',
              );
            }
            return _ok();
          });

          final response = await client.request<String>(
            'https://api.bilibili.com/source',
            options: Options(method: method),
          );

          expect(response.statusCode, 200);
          expect(adapter.requests, hasLength(3));
          expect(
            adapter.requests.every((request) => request.method == method),
            isTrue,
          );
        },
      );
    }

    for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
      test('$method is never repeated after a connection error', () async {
        final adapter = configure((options, _) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'request may already have reached the server',
          );
        });

        await expectLater(
          client.request<void>(
            'https://api.bilibili.com/write',
            data: 'a write operation',
            options: Options(method: method),
          ),
          throwsA(isA<DioException>()),
        );
        expect(adapter.requests, hasLength(1));
      });
    }

    test('stops retrying when the configured count is exhausted', () async {
      final adapter = configure((options, _) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'still offline',
        );
      });

      await expectLater(
        client.get<void>('https://api.bilibili.com/source'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(3));
    });

    test('does not requeue a request whose token was cancelled', () async {
      final token = CancelToken();
      final adapter = configure((options, _) {
        token.cancel('page closed');
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'connection closed while cancelling',
        );
      });

      await expectLater(
        client.get<void>(
          'https://api.bilibili.com/source',
          cancelToken: token,
        ),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    test(
      'does not replay an HTTP/2 request that may have been received',
      () async {
        final adapter = configure((options, _) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: TransportConnectionException(0, 'connection interrupted'),
          );
        });

        await expectLater(
          client.get<void>('https://api.bilibili.com/source'),
          throwsA(isA<DioException>()),
        );
        expect(adapter.requests, hasLength(1));
      },
    );

    for (final type in [
      DioExceptionType.cancel,
      DioExceptionType.badCertificate,
      DioExceptionType.receiveTimeout,
    ]) {
      test('does not retry $type', () async {
        final adapter = configure((options, _) {
          throw DioException(requestOptions: options, type: type);
        });

        await expectLater(
          client.get<void>('https://api.bilibili.com/source'),
          throwsA(
            isA<DioException>().having((error) => error.type, 'type', type),
          ),
        );
        expect(adapter.requests, hasLength(1));
      });
    }

    test('does not retry an HTTP error response', () async {
      final adapter = configure(
        (_, _) => ResponseBody.fromString('error', 503),
      );

      await expectLater(
        client.get<void>('https://api.bilibili.com/source'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('does not restart a streaming response', () async {
      final adapter = configure((options, _) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'stream interrupted',
        );
      });

      await expectLater(
        client.get<ResponseBody>(
          'https://api.bilibili.com/source',
          options: Options(responseType: ResponseType.stream),
        ),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
    });
  });
}
