import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/path_utils.dart' as paths;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

class _QueueRecorder extends DownloadService {
  final started = <int>[];
  final lastStarted = Completer<void>();

  @override
  Future<void> queueDownload(BiliDownloadEntryInfo entry) async {
    started.add(entry.cid);
    if (entry.cid == 8) lastStarted.complete();
  }
}

Future<File> _seed(Directory root, int cid, {bool completed = false}) async {
  final folder = Directory(path.join(root.path, '$cid', 'c_$cid'));
  await folder.create(recursive: true);
  final entry = BiliDownloadEntryInfo(
    isCompleted: completed,
    totalBytes: 100,
    downloadedBytes: completed ? 100 : 40,
    title: 'cached $cid',
    cover: '',
    preferedVideoQuality: 64,
    guessedTotalBytes: 100,
    totalTimeMilli: 1000,
    danmakuCount: 0,
    avid: cid,
    bvid: 'BV$cid',
    pageData: PageInfo(cid: cid, page: 1, hasAlias: false, tid: 0),
  );
  return File(path.join(folder.path, 'entry.json'))
      .writeAsString(jsonEncode(entry.toJson()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Directory a;
  late Directory b;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('piliminus-library-');
    a = Directory(path.join(temp.path, 'a'));
    b = Directory(path.join(temp.path, 'b'));
  });
  tearDown(() => temp.delete(recursive: true));

  test(
    'switching roots replaces both lists and keeps paused files on disk',
    () async {
      final manifest = await _seed(a, 1);
      await _seed(a, 3, completed: true);
      await _seed(b, 2);
      await _seed(b, 4, completed: true);
      final bytes = await manifest.readAsBytes();
      paths.downloadPath = a.path;
      final service = DownloadService()..onInit();
      await service.waitForInitialization;
      final old = service.waitDownloadQueue.single;
      service.curDownload.value = old..status = DownloadStatus.pause;
      var updates = 0;
      service.flagNotifier.add(() => updates++);

      paths.downloadPath = b.path;
      service.initDownloadList();
      await service.waitForInitialization;
      expect(service.downloadList.single.cid, 4);
      expect(service.waitDownloadQueue.single.cid, 2);
      expect(service.curDownload.value, isNull);
      expect(await manifest.readAsBytes(), bytes);

      paths.downloadPath = a.path;
      service.initDownloadList();
      await service.waitForInitialization;
      service.initDownloadList();
      await service.waitForInitialization;
      expect(service.downloadList.single.cid, 3);
      expect(service.waitDownloadQueue.single.cid, 1);
      expect(service.waitDownloadQueue.single.status, DownloadStatus.wait);
      expect(updates, 3);
    },
  );

  test('overlapping scans only publish the last selected directory', () async {
    final c = Directory(path.join(temp.path, 'c'));
    await _seed(a, 1);
    await _seed(b, 2);
    await _seed(c, 3);
    await _seed(c, 4, completed: true);
    paths.downloadPath = a.path;
    final service = DownloadService()..onInit();
    final startup = service.waitForInitialization;
    var updates = 0;
    service.flagNotifier.add(() => updates++);
    paths.downloadPath = b.path;
    service.initDownloadList();
    final second = service.waitForInitialization;
    paths.downloadPath = c.path;
    service.initDownloadList();

    await Future.wait([startup, second, service.waitForInitialization]);
    expect(service.waitDownloadQueue.single.cid, 3);
    expect(service.downloadList.single.cid, 4);
    expect(updates, 1);
  });

  test(
    'queued additions wait for the selected scan and deduplicate CIDs',
    () async {
      final existing = await _seed(b, 5, completed: true);
      final before = await existing.readAsBytes();
      paths.downloadPath = a.path;
      final service = _QueueRecorder()..onInit();
      void add(int cid) => service.downloadVideo(
        page: Part(page: 1, cid: cid),
        videoDetail: VideoDetailData(
          aid: cid,
          bvid: 'BV$cid',
          title: 'new',
          pic: '',
        ),
        videoQuality: VideoQuality.high1080,
      );
      add(1);
      paths.downloadPath = b.path;
      service.initDownloadList();
      add(5);
      add(7);
      add(7);
      add(8);
      await service.lastStarted.future;
      expect(service.started, [7, 8]);
      expect(service.waitDownloadQueue.map((e) => e.cid), [7, 8]);
      expect(service.downloadList.single.cid, 5);
      expect(await existing.readAsBytes(), before);
      expect(
        File(path.join(b.path, '1', 'c_1', 'entry.json')).existsSync(),
        isFalse,
      );
    },
  );
}
