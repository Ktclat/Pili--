import 'dart:async';

import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/pages/link_recognition/view.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Settings extends Fake implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}

void main() {
  testWidgets(
    'selecting a video waits for page information and remains retryable',
    (
      tester,
    ) async {
      const bvid = 'BV17x411w7KC';
      const url = 'https://www.bilibili.com/video/$bvid';
      const failure = '暂时无法打开视频，请核对链接后重试';
      final requests = <RequestOptions>[];
      final responses = <Completer<Map<String, dynamic>>>[];

      GStorage.setting = _Settings();
      Request();
      Request.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(options);
            final result = Completer<Map<String, dynamic>>();
            responses.add(result);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: await result.future,
              ),
            );
          },
        ),
      );
      addTearDown(() => Request.dio.close());
      addTearDown(Get.reset);

      Map? opened;
      await tester.pumpWidget(
        GetMaterialApp(
          home: const LinkRecognitionPage(),
          builder: FlutterSmartDialog.init(),
          navigatorObservers: [FlutterSmartDialog.observer],
          getPages: [
            GetPage(
              name: '/videoV',
              page: () {
                opened = Get.arguments as Map;
                return const Scaffold(body: Text('原生视频页'));
              },
            ),
          ],
        ),
      );
      await tester.enterText(find.byType(TextField), bvid);
      final recognize = find.widgetWithText(FilledButton, '识别');

      Future<void> select() async {
        await tester.ensureVisible(recognize);
        await tester.tap(recognize);
        await tester.pumpAndSettle();
        final count = requests.length;
        await tester.tap(find.text(url));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(requests.length, count + 1);
        expect(requests.last.path, Api.ab2c);
        expect(requests.last.queryParameters, {'aid': 170001, 'bvid': bvid});
        expect(opened, isNull);
        expect(tester.widget<FilledButton>(recognize).onPressed, isNull);
      }

      for (final noPage in [
        <String, dynamic>{'code': 0, 'data': []},
        <String, dynamic>{'code': -404, 'message': '视频暂不可用'},
      ]) {
        await select();
        responses.last.complete(noPage);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(failure), findsOneWidget);
        expect(tester.widget<FilledButton>(recognize).onPressed, isNotNull);
        expect(opened, isNull);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }

      await select();
      responses.last.complete({
        'code': 0,
        'data': [
          {
            'cid': 279786,
            'dimension': {'width': 640, 'height': 480},
          },
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('原生视频页'), findsOneWidget);
      expect(Get.currentRoute, '/videoV');
      expect(opened?['cid'], 279786);
      expect(opened?['aid'], 170001);
      expect(opened?['bvid'], bvid);
      expect(tester.takeException(), isNull);
    },
  );
}
