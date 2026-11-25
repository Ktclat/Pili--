import 'dart:async';

import 'package:PiliPlus/common/widgets/dialog/update_dialog.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/release_info.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/update.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Settings extends Fake implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}

final _release = ReleaseInfo.fromLatest({
  'tag_name': 'v0.6.4',
  'draft': false,
  'prerelease': false,
  'body': '版本更新说明',
})!;
const _apk =
    'https://github.com/Ktclat/Pili--/releases/download/v0.6.4/PiliMinus-arm64-v8a.apk';

Future<void> _mount(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: FlutterSmartDialog.init(),
      navigatorObservers: [FlutterSmartDialog.observer],
      home: const Scaffold(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a manual check joins the automatic request and receives feedback',
    (tester) async {
      GStorage.setting = _Settings();
      await _mount(tester);
      Request();
      final requests = <RequestOptions>[];
      final response = Completer<void>();
      final interceptor = InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add(options);
          await response.future;
          handler.resolve(
            Response<void>(requestOptions: options, statusCode: 404),
          );
        },
      );
      Request.dio.interceptors.add(interceptor);
      addTearDown(() => Request.dio.interceptors.remove(interceptor));

      final automatic = Update.checkStableRelease(true);
      await tester.pump(const Duration(milliseconds: 20));
      expect(requests.map((request) => request.path), [Api.latestApp]);
      final manual = Update.checkStableRelease(false);
      expect(manual, same(automatic));
      response.complete();
      await tester.pump(const Duration(milliseconds: 20));
      await manual;
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(find.text('暂无正式发布版本'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final next = Update.checkStableRelease(true);
      await tester.pump(const Duration(milliseconds: 20));
      await next;
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(find.text('暂无正式发布版本'), findsNothing);
    },
  );

  testWidgets(
    'a failed check can retry and only one verified link is returned',
    (tester) async {
      await _mount(tester);
      final attempts = <Completer<AndroidUpgradeResult>>[];
      final result = showUpdateDialog(
        _release,
        checkAndroid: () {
          final pending = Completer<AndroidUpgradeResult>();
          attempts.add(pending);
          return pending.future;
        },
      );
      await tester.pumpAndSettle();
      expect(attempts, isEmpty);
      await tester.tap(find.text('下载更新'));
      await tester.tap(find.text('下载更新'));
      await tester.pump();
      expect(attempts, hasLength(1));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      attempts.single.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('查看发布页'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(attempts, hasLength(2));
      attempts.last.complete(const AndroidUpgradeResult.verified(_apk));
      await tester.pumpAndSettle();
      expect(await result, _apk);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'cancelling a pending check discards even a verified late response',
    (tester) async {
      await _mount(tester);
      final pending = Completer<AndroidUpgradeResult>();
      final result = showUpdateDialog(
        _release,
        checkAndroid: () => pending.future,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载更新'));
      await tester.pump();
      await tester.tap(find.text('取消'));
      pending.complete(const AndroidUpgradeResult.verified(_apk));
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an external dismissal while checking cannot close the next dialog',
    (tester) async {
      await _mount(tester);
      final pending = Completer<AndroidUpgradeResult>();
      final first = showUpdateDialog(
        _release,
        checkAndroid: () => pending.future,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载更新'));
      await tester.pump();
      await tester.tapAt(
        const Offset(6, 6),
      ); // Dismiss through the modal barrier.
      await tester.pumpAndSettle();
      expect(await first, isNull);
      final next = showUpdateDialog(_release);
      await tester.pumpAndSettle();
      pending.complete(const AndroidUpgradeResult.verified(_apk));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await next, isNull);
    },
  );

  testWidgets(
    'an incompatible signer explains backup and offers the release page',
    (tester) async {
      await _mount(tester);
      final result = showUpdateDialog(
        _release,
        checkAndroid: () async =>
            const AndroidUpgradeResult(AndroidUpgradeStatus.signerMismatch),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(find.textContaining('设置 → 关于 → 导入/导出所有数据'), findsOneWidget);
      expect(find.text('下载更新'), findsNothing);
      expect(find.text('重试'), findsNothing);
      expect(find.textContaining('离线视频需另行保留'), findsOneWidget);
      expect(find.text('查看发布页'), findsOneWidget);
      await tester.tap(find.text('迁移说明'));
      await tester.pumpAndSettle();
      expect(
        await result,
        'https://github.com/Ktclat/Pili--/blob/main/docs/INSTALL.md#旧测试签名迁移',
      );
    },
  );
}
