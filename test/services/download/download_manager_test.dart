import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/services/download/download_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Response = FutureOr<ResponseBody> Function(RequestOptions options);

class _Adapter implements HttpClientAdapter {
  final _Response respond;

  _Adapter(this.respond);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(
  String value,
  int status, {
  String? range,
  int? length,
}) => ResponseBody.fromBytes(
  utf8.encode(value),
  status,
  headers: {
    Headers.contentLengthHeader: ['${length ?? utf8.encode(value).length}'],
    if (range != null) 'content-range': [range],
  },
);

void main() {
  late Directory directory;
  late File file;
  late Dio client;
  late List<Object?> completions;
  late List<(int, int)> progress;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('piliminus-download-');
    file = File('${directory.path}/video.m4s');
    await file.writeAsString('abc');
    client = Dio();
    completions = [];
    progress = [];
  });

  tearDown(() async {
    client.close(force: true);
    await directory.delete(recursive: true);
  });

  DownloadManager start({void Function(int, int)? onProgress}) =>
      DownloadManager(
        url: 'https://media.example.test/video.m4s',
        path: file.path,
        client: client,
        onReceiveProgress: (received, total) {
          progress.add((received, total));
          onProgress?.call(received, total);
        },
        onDone: ([error]) => completions.add(error),
      );

  test(
    'a server ignoring Range replaces the prefix instead of appending',
    () async {
      client.httpClientAdapter = _Adapter((options) {
        expect(options.headers['range'], 'bytes=3-');
        expect(options.headers['accept-encoding'], 'identity');
        return _body('abcdef', 200);
      });

      final manager = start();
      await manager.task;

      expect(await file.readAsString(), 'abcdef');
      expect(manager.status, DownloadStatus.completed);
      expect(progress.first, (0, 6));
      expect(progress.last, (6, 6));
      expect(completions, [null]);
    },
  );

  test(
    'a matching partial response resumes at the existing byte offset',
    () async {
      client.httpClientAdapter = _Adapter((options) {
        expect(options.headers['range'], 'bytes=3-');
        return _body('def', 206, range: 'bytes 3-5/6');
      });

      final manager = start();
      await manager.task;

      expect(await file.readAsString(), 'abcdef');
      expect(manager.status, DownloadStatus.completed);
      expect(progress.last, (6, 6));
      expect(completions, [null]);
    },
  );

  test('a capped partial response fetches the remaining range', () async {
    final requestedRanges = <Object?>[];
    client.httpClientAdapter = _Adapter((options) {
      requestedRanges.add(options.headers['range']);
      return requestedRanges.length == 1
          ? _body('de', 206, range: 'bytes 3-4/6')
          : _body('f', 206, range: 'bytes 5-5/6');
    });

    final manager = start();
    await manager.task;

    expect(requestedRanges, ['bytes=3-', 'bytes=5-']);
    expect(await file.readAsString(), 'abcdef');
    expect(manager.status, DownloadStatus.completed);
    expect(completions, [null]);
  });

  test(
    'a new download creates its directory and validates its first range',
    () async {
      file = File('${directory.path}/new/video.m4s');
      client.httpClientAdapter = _Adapter((options) {
        expect(options.headers['range'], 'bytes=0-');
        return _body('abcdef', 206, range: 'bytes 0-5/6');
      });

      final manager = start();
      await manager.task;

      expect(await file.readAsString(), 'abcdef');
      expect(manager.status, DownloadStatus.completed);
      expect(completions, [null]);
    },
  );

  test('a chunked full response reports the actual final size', () async {
    client.httpClientAdapter = _Adapter(
      (_) => ResponseBody.fromBytes(utf8.encode('abcdef'), 200),
    );

    final manager = start();
    await manager.task;

    expect(await file.readAsString(), 'abcdef');
    expect(progress.first, (0, 0));
    expect(progress.last, (6, 6));
    expect(manager.status, DownloadStatus.completed);
    expect(completions, [null]);
  });

  for (final range in <String?>[
    null,
    'bytes 0-2/6',
    'bytes 3-6/6',
    'bytes 3-2/6',
    'bytes 3-5/*',
    'bytes 3-4/6',
  ]) {
    test(
      'an inconsistent Content-Range ($range) preserves the prefix',
      () async {
        client.httpClientAdapter = _Adapter(
          (_) => _body('def', 206, range: range),
        );

        final manager = start();
        await manager.task;

        expect(await file.readAsString(), 'abc');
        expect(manager.status, DownloadStatus.failDownload);
        expect(completions, [isA<HttpException>()]);
      },
    );
  }

  test(
    'a short partial body is retained for retry but never completed',
    () async {
      client.httpClientAdapter = _Adapter(
        (_) => _body('de', 206, range: 'bytes 3-5/6', length: 3),
      );

      final manager = start();
      await manager.task;

      expect(await file.readAsString(), 'abcde');
      expect(manager.status, DownloadStatus.failDownload);
      expect(completions, [isA<HttpException>()]);
    },
  );

  test(
    'an oversized partial body is not written beyond its declared range',
    () async {
      client.httpClientAdapter = _Adapter(
        (_) => _body('defERROR', 206, range: 'bytes 3-5/6', length: 3),
      );

      final manager = start();
      await manager.task;

      expect(await file.readAsString(), 'abc');
      expect(manager.status, DownloadStatus.failDownload);
      expect(completions, [isA<HttpException>()]);
    },
  );

  test('a short full response is not marked complete', () async {
    client.httpClientAdapter = _Adapter(
      (_) => _body('abcd', 200, length: 6),
    );

    final manager = start();
    await manager.task;

    expect(await file.readAsString(), 'abcd');
    expect(manager.status, DownloadStatus.failDownload);
    expect(completions, [isA<HttpException>()]);
  });

  test(
    '416 with matching total confirms completion without writing its body',
    () async {
      client.httpClientAdapter = _Adapter(
        (_) => _body('<html>range error</html>', 416, range: 'bytes */3'),
      );

      final manager = start();
      await manager.task;

      expect(await file.readAsString(), 'abc');
      expect(manager.status, DownloadStatus.completed);
      expect(progress.last, (3, 3));
      expect(completions, [null]);
    },
  );

  for (final range in <String?>[
    null,
    'bytes */2',
    'bytes */6',
    'bytes 0-2/3',
  ]) {
    test('416 without proof of completion ($range) is a failure', () async {
      client.httpClientAdapter = _Adapter(
        (_) => _body('<html>range error</html>', 416, range: range),
      );

      final manager = start();
      await manager.task;

      expect(await file.readAsString(), 'abc');
      expect(manager.status, DownloadStatus.failDownload);
      expect(completions, [isA<HttpException>()]);
    });
  }

  for (final status in [206, 416]) {
    test('an unused $status response stops its underlying stream', () async {
      final cancelled = Completer<void>();
      final source = StreamController<Uint8List>(
        onCancel: cancelled.complete,
      );
      client.httpClientAdapter = _Adapter(
        (_) => ResponseBody(
          source.stream,
          status,
          headers: {
            'content-range': [status == 416 ? 'bytes */3' : 'bytes 0-2/3'],
          },
        ),
      );

      final manager = start();
      await manager.task;
      await cancelled.future.timeout(const Duration(seconds: 2));
      await source.close();

      expect(await file.readAsString(), 'abc');
      expect(
        manager.status,
        status == 416 ? DownloadStatus.completed : DownloadStatus.failDownload,
      );
      expect(completions, hasLength(1));
    });
  }

  test('a failed request preserves a resumable file', () async {
    client.httpClientAdapter = _Adapter(
      (options) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'connection lost',
      ),
    );

    final manager = start();
    await manager.task;

    expect(await file.readAsString(), 'abc');
    expect(manager.status, DownloadStatus.failDownload);
    expect(completions, [isA<DioException>()]);
  });

  test(
    '204 cannot turn an unfinished file into a completed download',
    () async {
      client.httpClientAdapter = _Adapter((_) => _body('', 204));

      final manager = start();
      await manager.task;

      expect(await file.readAsString(), 'abc');
      expect(manager.status, DownloadStatus.failDownload);
      expect(completions, [isA<DioException>()]);
    },
  );

  test('pausing after response headers preserves the old prefix', () async {
    client.httpClientAdapter = _Adapter((_) => _body('abcdef', 200));
    late DownloadManager manager;
    manager = start(
      onProgress: (_, _) => unawaited(manager.cancel(isDelete: false)),
    );
    await manager.task;

    expect(await file.readAsString(), 'abc');
    expect(manager.status, DownloadStatus.pause);
    expect(completions, [isA<DioException>()]);
  });

  for (final isDelete in [false, true]) {
    test(
      'cancelling the final chunk does not report completion (delete: $isDelete)',
      () async {
        client.httpClientAdapter = _Adapter(
          (_) => _body('def', 206, range: 'bytes 3-5/6'),
        );
        late DownloadManager manager;
        manager = start(
          onProgress: (received, _) {
            if (received == 6) {
              unawaited(manager.cancel(isDelete: isDelete));
            }
          },
        );
        await manager.task;

        expect(await file.readAsString(), 'abcdef');
        expect(
          manager.status,
          isDelete ? DownloadStatus.failDownload : DownloadStatus.pause,
        );
        expect(completions, [isA<DioException>()]);
      },
    );
  }
}
