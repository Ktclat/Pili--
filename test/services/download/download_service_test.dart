import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/path_utils.dart' as paths;
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';
import 'package:flutter_test/flutter_test.dart';

class _DownloadService extends DownloadService {
  int nextCalls = 0;

  @override
  void nextDownload() => nextCalls++;
}

class _BlockedDanmaku extends _DownloadService {
  final started = Completer<void>();
  final response = Completer<bool>();

  @override
  Future<bool> downloadDanmaku({
    required BiliDownloadEntryInfo entry,
    bool isUpdate = false,
  }) {
    entry.status = DownloadStatus.getDanmaku;
    started.complete();
    return response.future;
  }
}

class _Settings extends Fake implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) {
    if (key == LocalCacheKey.mixinKey) return 'cached-wbi-key';
    if (key == LocalCacheKey.timeStamp) {
      return DateTime.now().millisecondsSinceEpoch;
    }
    return defaultValue;
  }
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

  Subtitle track(int id) =>
      Subtitle(id: id, lan: 'zh-CN', subtitleUrl: 'https://example.test/$id');

  Future<List<LocalSubtitle>> readTracks(BiliDownloadEntryInfo video) async {
    final saved = jsonDecode(
      await File('${video.entryDirPath}/entry.json').readAsString(),
    ) as Map<String, dynamic>;
    return BiliDownloadEntryInfo.fromJson(
      saved,
      video.entryDirPath,
    ).subtitles!.cast<LocalSubtitle>();
  }

  test(
    'metadata switches only after all subtitle files are readable',
    () async {
      final video = entry(1);
      final fetching = Completer<void>();
      final response = Completer<List<int>>();
      final saving = service.savePlayInfo(
        video,
        [track(2)],
        null,
        fetch: (_) {
          fetching.complete();
          return response.future;
        },
      );
      await fetching.future;
      expect(video.subtitles, isNull);
      expect(File('${video.entryDirPath}/entry.json').existsSync(), isFalse);

      response.complete(utf8.encode('{"body":[]}'));
      await saving;
      final saved = (await readTracks(video)).single;
      expect(await File(saved.path).readAsString(), '{"body":[]}');
      expect(saved.id, 2);
    },
  );

  test(
    'a partial refresh preserves legacy tracks, then retries the full set',
    () async {
      final video = entry(1);
      final oldTrack = track(1).toLocal(video.entryDirPath);
      final oldFile = File(oldTrack.path);
      await oldFile.create(recursive: true);
      await oldFile.writeAsString('previous');
      video.subtitles = [oldTrack];
      final manifest = File('${video.entryDirPath}/entry.json');
      await manifest.writeAsString(jsonEncode(video.toJson()));
      final before = await manifest.readAsString();
      final second = track(2);
      final firstWritten = Completer<void>();
      final fail = Completer<List<int>?>();
      final saving = service.savePlayInfo(
        video,
        [track(1), second],
        null,
        fetch: (url) async {
          if (url == second.subtitleUrl) return fail.future;
          firstWritten.complete();
          return utf8.encode('replacement');
        },
      );
      await firstWritten.future;
      fail.complete(null);
      await expectLater(saving, throwsFormatException);
      expect(await manifest.readAsString(), before);
      expect(
        await File((await readTracks(video)).single.path).readAsString(),
        'previous',
      );
      expect(oldFile.parent.listSync().map((item) => item.path), [
        oldFile.path,
      ]);

      await service.savePlayInfo(
        video,
        [track(1), second],
        null,
        fetch: (_) async => utf8.encode('new'),
      );
      final saved = await readTracks(video);
      expect(saved.map((sub) => sub.id), [1, 2]);
      expect(saved[0].batch, isNotNull);
      expect(saved[1].batch, saved[0].batch);
      for (final sub in saved) {
        expect(await File(sub.path).readAsString(), 'new');
      }
      expect(await oldFile.readAsString(), 'previous');
    },
  );

  test(
    'failed metadata replacement keeps the previous generation readable',
    () async {
      final video = entry(1);
      await service.savePlayInfo(
        video,
        [track(1), track(2)],
        null,
        fetch: (_) async => [1],
      );
      final saved = await readTracks(video);
      await Directory('${video.entryDirPath}/entry.json.tmp').create();
      await expectLater(
        service.savePlayInfo(
          video,
          [track(1), track(2)],
          null,
          fetch: (_) async => [2],
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        (await readTracks(video)).map((s) => s.path),
        saved.map((s) => s.path),
      );
      expect(
        video.subtitles!.cast<LocalSubtitle>().map((s) => s.path),
        saved.map((s) => s.path),
      );
      for (final sub in saved) {
        expect(await File(sub.path).readAsBytes(), [1]);
      }
    },
  );

  test('overlapping subtitle updates publish coherent file sets', () async {
    final video = entry(1);
    final waiting = Completer<void>();
    final delayed = Completer<List<int>>();
    final first = service.savePlayInfo(
      video,
      [track(1), track(2)],
      null,
      fetch: (url) async {
        if (url.endsWith('/2')) {
          waiting.complete();
          return delayed.future;
        }
        return [1];
      },
    );
    await waiting.future;
    await service.savePlayInfo(
      video,
      [track(1), track(2)],
      null,
      fetch: (_) async => [2],
    );
    final before = await readTracks(video);
    delayed.complete([1]);
    await first;
    final after = await readTracks(video);
    expect(after.first.batch, isNot(before.first.batch));
    for (final sub in before) {
      expect(await File(sub.path).readAsBytes(), [2]);
    }
    for (final sub in after) {
      expect(await File(sub.path).readAsBytes(), [1]);
    }

    // Reload from another directory just as after moving an existing cache.
    TestWidgetsFlutterBinding.ensureInitialized();
    final page = await Directory('${directory.path}/page').create();
    final moved = await Directory(video.entryDirPath).rename('${page.path}/1');
    paths.downloadPath = directory.path;
    final restarted = _DownloadService()..onInit();
    await restarted.waitForInitialization;
    final restored = restarted.waitDownloadQueue.single;
    final currentTracks = restored.subtitles!.cast<LocalSubtitle>();
    expect(currentTracks.first.path, startsWith(moved.path));
    for (final sub in currentTracks) {
      expect(await File(sub.path).readAsBytes(), [1]);
    }
    final dir = Directory('${moved.path}/${paths.PathUtils.subtitleDir}');
    expect(dir.listSync().map((sub) => sub.path), [
      '${dir.path}/${after.first.batch}',
    ]);
  });

  test('a paused preparation ignores the late danmaku response', () async {
    final blocked = _BlockedDanmaku();
    final video = entry(1);
    blocked.waitDownloadQueue.add(video);
    final preparing = blocked.queueDownload(video);
    await blocked.started.future;
    await blocked.cancelDownload(isDelete: false, downloadNext: false);
    blocked.response.complete(true);
    await preparing;

    expect(video.status, DownloadStatus.pause);
    expect(blocked.curDownload.value, same(video));
    expect(blocked.waitDownloadQueue, [video]);
    expect(blocked.nextCalls, 0);
  });

  test(
    'deleting while waiting for the play URL cannot recreate the files',
    () async {
      final video = entry(1);
      final folder = Directory(video.entryDirPath);
      await Directory('${directory.path}/another-entry').create();
      await File('${folder.path}/${paths.PathUtils.danmakuName}').create();
      final requested = Completer<void>();
      final release = Completer<void>();
      GStorage.setting = _Settings();
      GStorage.localCache = _Settings();
      Request();
      Request.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            if (options.uri.path.endsWith('/finger/spi')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'code': 0,
                    'data': {'b_3': 'guest', 'b_4': 'guest'},
                  },
                ),
              );
              return;
            }
            expect(options.uri.path, contains('playurl'));
            requested.complete();
            await release.future;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'code': 0,
                  'data': {
                    'format': 'mp4',
                    'quality': 32,
                    'durl': [
                      {
                        'url': 'https://example.test/video.mp4',
                        'order': 1,
                        'size': 3,
                        'length': 100,
                      },
                    ],
                  },
                },
              ),
            );
          },
        ),
      );
      addTearDown(() => Request.dio.close(force: true));
      service.waitDownloadQueue.add(video);
      final preparing = service.queueDownload(video);
      await requested.future;
      await service.deleteDownload(
        entry: video,
        removeQueue: true,
        downloadNext: false,
      );
      expect(folder.existsSync(), isFalse);
      release.complete();
      await preparing;

      expect(folder.existsSync(), isFalse);
      expect(service.curDownload.value, isNull);
      expect(service.waitDownloadQueue, isEmpty);
      expect(video.videoQuality, isNull);
    },
  );

  test('retrying a deletion leaves a sibling download intact', () async {
    final first = entry(1);
    final sibling = entry(2);
    final media = File('${sibling.entryDirPath}/video.m4s');
    await media.writeAsBytes([1, 2, 3]);
    service.downloadList.addAll([first, sibling]);
    await service.deleteDownload(entry: first, removeList: true);
    await service.deleteDownload(entry: first, removeList: true);
    expect(await media.readAsBytes(), [1, 2, 3]);
    expect(service.downloadList, [sibling]);
  });

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
    // File.writeAsString has yielded, as when queueDownload selects another
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
