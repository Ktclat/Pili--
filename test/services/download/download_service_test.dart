import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _DownloadService extends DownloadService {
  int nextCalls = 0;

  @override
  void nextDownload() => nextCalls++;
}

void main() {
  late Directory directory;
  late _DownloadService service;

  BiliDownloadEntryInfo entry(int cid) {
    final folder = Directory('${directory.path}/$cid')..createSync();
    return BiliDownloadEntryInfo(
        isCompleted: false,
        totalBytes: 6,
        downloadedBytes: 6,
        title: 'Video $cid',
        cover: '',
        preferedVideoQuality: 64,
        guessedTotalBytes: 6,
        totalTimeMilli: 1000,
        danmakuCount: 0,
        avid: cid,
        bvid: 'BV$cid',
        pageData: PageInfo(cid: cid, page: 1, hasAlias: false, tid: 0),
      )
      ..pageDirPath = directory.path
      ..entryDirPath = folder.path
      ..status = DownloadStatus.downloading;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('piliminus-completion-');
    service = _DownloadService();
  });

  tearDown(() => directory.delete(recursive: true));

  test('completion persists the entry and advances the queue once', () async {
    final finished = entry(1);
    service.waitDownloadQueue.add(finished);
    service.curDownload.value = finished;

    await service.completeDownload();

    final saved = jsonDecode(
      await File('${finished.entryDirPath}/entry.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(saved['is_completed'], isTrue);
    expect(saved['downloaded_bytes'], 6);
    expect(service.downloadList, [finished]);
    expect(service.waitDownloadQueue, isEmpty);
    expect(service.curDownload.value, isNull);
    expect(service.nextCalls, 1);
  });

  test('a late metadata write cannot clear a newer active download', () async {
    final finished = entry(1);
    final active = entry(2);
    service.waitDownloadQueue.addAll([finished, active]);
    service.curDownload.value = finished;

    final completion = service.completeDownload();
    // File.writeAsString has yielded, as when startDownload selects another
    // queued task while the previous manager's void onDone callback finishes.
    service.curDownload.value = active;
    await completion;

    expect(service.curDownload.value, same(active));
    expect(active.status, DownloadStatus.downloading);
    expect(service.waitDownloadQueue, [active]);
    expect(service.downloadList, [finished]);
    expect(service.nextCalls, 0);
  });

  test(
    'simultaneous audio and video completion only records one entry',
    () async {
      final finished = entry(1);
      service.waitDownloadQueue.add(finished);
      service.curDownload.value = finished;
      var notifications = 0;
      service.flagNotifier.add(() => notifications++);

      await Future.wait([
        service.completeDownload(),
        service.completeDownload(),
      ]);

      expect(service.downloadList, [finished]);
      expect(notifications, 1);
      expect(service.nextCalls, 1);
    },
  );

  test('a deleted queue entry is not restored by a late completion', () async {
    final finished = entry(1);
    service.waitDownloadQueue.add(finished);
    service.curDownload.value = finished;

    final completion = service.completeDownload();
    service.waitDownloadQueue.remove(finished);
    service.curDownload.value = null;
    await completion;

    expect(service.downloadList, isEmpty);
    expect(service.waitDownloadQueue, isEmpty);
    expect(service.curDownload.value, isNull);
    expect(service.nextCalls, 0);
  });

  test(
    'metadata failures remain retryable without advancing the queue',
    () async {
      final finished = entry(1);
      service.waitDownloadQueue.add(finished);
      service.curDownload.value = finished;
      await Directory(finished.entryDirPath).delete();

      await service.completeDownload();

      expect(finished.isCompleted, isFalse);
      expect(finished.status, DownloadStatus.failDownload);
      expect(service.curDownload.value, same(finished));
      expect(service.downloadList, isEmpty);
      expect(service.waitDownloadQueue, [finished]);
      expect(service.nextCalls, 0);

      await Directory(finished.entryDirPath).create();
      await service.completeDownload();
      expect(finished.isCompleted, isTrue);
      expect(service.downloadList, [finished]);
      expect(service.nextCalls, 1);
    },
  );

  test(
    'a failed old metadata write leaves a newer download unchanged',
    () async {
      final finished = entry(1);
      final active = entry(2);
      service.waitDownloadQueue.addAll([finished, active]);
      service.curDownload.value = finished;
      await Directory(finished.entryDirPath).delete();

      final completion = service.completeDownload();
      service.curDownload.value = active;
      await completion;

      expect(finished.isCompleted, isFalse);
      expect(finished.status, DownloadStatus.failDownload);
      expect(service.curDownload.value, same(active));
      expect(active.status, DownloadStatus.downloading);
      expect(service.downloadList, isEmpty);
      expect(service.nextCalls, 0);
    },
  );
}
