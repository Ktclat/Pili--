import 'package:PiliPlus/pages/link_recognition/view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _PageObserver extends NavigatorObserver {
  final openedPages = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute<dynamic>) openedPages.add(route);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const link = 'https://www.bilibili.com/video/BV1xx411c7mD';
  const pasteLabel = '从剪贴板粘贴并识别';
  const failure = '未识别到可打开的 B 站链接或 BV/av 号，请检查内容。';
  var reads = 0;
  String? clipboardText;
  late _PageObserver observer;

  setUp(() {
    reads = 0;
    clipboardText = '分享这个视频：$link';
    observer = _PageObserver();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            reads++;
            return clipboardText == null ? null : {'text': clipboardText};
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboardText?.isNotEmpty ?? false};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> showPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const LinkRecognitionPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'clipboard is read only after the paste action and cancel stays on the page',
    (
      tester,
    ) async {
      await showPage(tester);
      expect(reads, 0);
      expect(observer.openedPages.length, 1);

      await tester.ensureVisible(find.text(pasteLabel));
      await tester.tap(find.text(pasteLabel));
      await tester.pumpAndSettle();

      expect(reads, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('识别到哔哩哔哩链接'), findsOneWidget);
      expect(find.text(link), findsOneWidget);
      // A confirmation route may open; a content page must wait for a selection.
      expect(observer.openedPages.length, 1);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LinkRecognitionPage), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(observer.openedPages.length, 1);
      expect(reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final input in [
    'ordinary unrelated text',
    'https://bilibili.com.evil.example/video/BV1xx411c7mD',
  ]) {
    testWidgets(
      'manual invalid input is rejected without reading the clipboard: $input',
      (
        tester,
      ) async {
        await showPage(tester);
        await tester.enterText(find.byType(TextField), input);
        await tester.ensureVisible(find.widgetWithText(FilledButton, '识别'));
        await tester.tap(find.widgetWithText(FilledButton, '识别'));
        await tester.pumpAndSettle();

        expect(find.text(failure), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(observer.openedPages.length, 1);
        expect(reads, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
