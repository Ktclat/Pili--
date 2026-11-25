import 'dart:async';

import 'package:PiliPlus/pages/link_recognition/view.dart';
import 'package:PiliPlus/pages/scan/authorization.dart';
import 'package:PiliPlus/pages/scan/view.dart';
import 'package:PiliPlus/router/app_pages.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

const _loginLink =
    'https://account.bilibili.com/h5/account-h5/auth/scan-web?qrcode_key=0123456789abcdef0123456789abcdef';

Future<void> _showScanner(
  WidgetTester tester, {
  String route = '/scan',
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    GetMaterialApp(
      getPages: Routes.getPages
          .where(
            (page) => const {
              '/scan',
              '/scanLogin',
              '/recognizeLink',
            }.contains(page.name),
          )
          .toList(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Get.toNamed(route),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var reads = 0;
  late Future<String?> Function() read;
  setUp(() {
    reads = 0;
    read = () async => _loginLink;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        reads++;
        return {'text': await read()};
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    Get.reset();
  });

  for (final route in ['/scan', '/scanLogin']) {
    testWidgets(
      '$route opens the unified scanner without reading the clipboard',
      (
        tester,
      ) async {
        await _showScanner(tester, route: route);
        expect(find.text('扫一扫'), findsOneWidget);
        expect(find.text('粘贴登录链接'), findsOneWidget);
        expect(find.byTooltip('识别链接'), findsOneWidget);
        expect(reads, 0);
      },
    );
  }

  testWidgets(
    'scanner app bar opens link recognition and returns to scanning',
    (
      tester,
    ) async {
      await _showScanner(tester);
      final appBar = find.byType(AppBar);
      final link = find.descendant(
        of: appBar,
        matching: find.byTooltip('识别链接'),
      );
      expect(tester.widget<AppBar>(appBar).actions, hasLength(1));
      expect(
        tester.getCenter(link).dx,
        greaterThan(tester.getCenter(appBar).dx),
      );
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.byType(LinkRecognitionPage), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(reads, 0);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(link, findsOneWidget);
      expect(find.text('粘贴登录链接'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a deliberate paste opens one account confirmation without a camera',
    (tester) async {
      tester.view.physicalSize = const Size(320, 250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<String?>();
      read = () => pending.future;
      await _showScanner(tester);
      expect(reads, 0);
      final action = find.text('粘贴登录链接');
      await tester.tap(action);
      await tester.tap(action);
      expect(reads, 1);
      pending.complete(_loginLink);
      await tester.pumpAndSettle();
      expect(find.byType(QrLoginAuthorizationPage), findsOneWidget);
      expect(find.textContaining('0123456789abcdef'), findsNothing);
      expect(find.byType(ScanPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('non-login clipboard contents stay on the scanner', (
    tester,
  ) async {
    read = () async => 'https://www.bilibili.com/video/BV17x411w7KC';
    await _showScanner(tester);
    await tester.tap(find.text('粘贴登录链接'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请先复制哔哩哔哩'), findsOneWidget);
    expect(find.byType(ScanPage), findsOneWidget);
    expect(find.byType(QrLoginAuthorizationPage), findsNothing);
    expect(find.textContaining('BV17x411w7KC'), findsNothing);
    expect(reads, 1);
  });

  testWidgets('leaving the app discards a pending clipboard result', (
    tester,
  ) async {
    final pending = Completer<String?>();
    read = () => pending.future;
    await _showScanner(tester);
    await tester.tap(find.text('粘贴登录链接'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    pending.complete(_loginLink);
    await tester.pumpAndSettle();
    expect(find.byType(ScanPage), findsOneWidget);
    expect(find.byType(QrLoginAuthorizationPage), findsNothing);
    expect(reads, 1);
  });
}
