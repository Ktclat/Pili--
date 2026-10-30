import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:dio/dio.dart';

class DownloadManager {
  final String url;
  final String path;
  final void Function(int, int)? onReceiveProgress;
  final void Function([Object? error]) onDone;
  final Dio? client;

  DownloadStatus _status = DownloadStatus.downloading;

  DownloadStatus get status => _status;
  final _cancelToken = CancelToken();
  late Future<void> task;

  DownloadManager({
    required this.url,
    required this.path,
    required this.onReceiveProgress,
    required this.onDone,
    this.client,
  }) {
    task = _start();
  }

  Future<void> _start() async {
    Object? error;
    try {
      await _download();
      _checkCancelled();
      _status = DownloadStatus.completed;
    } catch (e) {
      error = e;
      if (_status == DownloadStatus.downloading) {
        _status = DownloadStatus.failDownload;
      }
    }
    // Cancelling a ResponseBody listener alone does not stop every Dio adapter.
    // The request token also releases rejected ranges and ignored 416 bodies.
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
    onDone(error);
  }

  void _checkCancelled() {
    if (_cancelToken.isCancelled) {
      throw _cancelToken.cancelError!;
    }
  }

  Future<void> _download() async {
    final file = File(path);
    var received = file.existsSync() ? await file.length() : 0;
    final client = this.client ?? Request.http11Dio;

    int? last;
    while (true) {
      _checkCancelled();
      final response = await client.get<ResponseBody>(
        url.http2https,
        options: Options(
          headers: {
            'range': 'bytes=$received-',
            // Byte ranges and file offsets must refer to the same representation.
            'accept-encoding': 'identity',
          },
          responseType: ResponseType.stream,
          validateStatus: (status) =>
              status == 200 || status == 206 || status == 416,
        ),
        cancelToken: _cancelToken,
      );
      final data = response.data!;
      RandomAccessFile? output;
      var streamStarted = false;
      try {
        _checkCancelled();
        final contentRange = response.headers.value('content-range');
        if (response.statusCode == 416) {
          final match = RegExp(r'^bytes \*/(\d+)$').firstMatch(
            contentRange ?? '',
          );
          final total = match == null ? null : int.tryParse(match[1]!);
          // A 416 body is an error page, never media data. It only proves a
          // previous download finished when the server confirms its exact size.
          if (received > 0 && total == received) {
            onReceiveProgress?.call(received, received);
            return;
          }
          throw const HttpException('Download range is not satisfiable');
        }

        final encoding = response.headers.value('content-encoding');
        if (encoding != null && encoding.toLowerCase() != 'identity') {
          throw const HttpException(
            'Encoded download cannot be resumed safely',
          );
        }

        int? total;
        int? expectedLength;
        if (response.statusCode == 206) {
          final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(
            contentRange ?? '',
          );
          final start = match == null ? null : int.tryParse(match[1]!);
          final end = match == null ? null : int.tryParse(match[2]!);
          total = match == null ? null : int.tryParse(match[3]!);
          if (start != received ||
              end == null ||
              total == null ||
              end < received ||
              end >= total) {
            throw const HttpException('Invalid download Content-Range');
          }
          expectedLength = end - received + 1;
          if (data.contentLength >= 0 && data.contentLength != expectedLength) {
            throw const HttpException('Download range length does not match');
          }
        } else {
          // Servers may ignore Range. A complete response replaces the old
          // prefix; appending it would silently corrupt an otherwise valid file.
          received = 0;
          if (data.contentLength >= 0) {
            total = expectedLength = data.contentLength;
          }
        }

        onReceiveProgress?.call(received, total ?? 0);
        _checkCancelled();
        await file.parent.create(recursive: true);
        _checkCancelled();
        output = await file.open(
          mode: received == 0 ? FileMode.write : FileMode.append,
        );
        var responseBytes = 0;
        streamStarted = true;
        await for (final chunk in data.stream) {
          _checkCancelled();
          if (expectedLength != null &&
              responseBytes + chunk.length > expectedLength) {
            throw const HttpException('Download exceeds its declared length');
          }
          await output.writeFrom(chunk);
          received += chunk.length;
          responseBytes += chunk.length;
          _checkCancelled();
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (last != now) {
            last = now;
            onReceiveProgress?.call(received, total ?? 0);
          }
        }
        _checkCancelled();
        if (expectedLength != null && responseBytes != expectedLength) {
          throw const HttpException(
            'Download ended before its declared length',
          );
        }
        await output.flush();
        await output.close();
        output = null;
        if (await file.length() != received) {
          throw const FileSystemException(
            'Downloaded file length does not match',
          );
        }
        _checkCancelled();
        onReceiveProgress?.call(received, total ?? received);
        if (total == null || received == total) {
          return;
        }
        // Some servers cap a range response. Fetch the next range instead of
        // marking an incomplete file as complete.
      } finally {
        await output?.close();
        if (!streamStarted) {
          await data.stream.listen(null).cancel();
        }
      }
    }
  }

  Future<void> cancel({required bool isDelete}) {
    if (!isDelete && _status == DownloadStatus.downloading) {
      _status = DownloadStatus.pause;
    }
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
    return task;
  }
}
