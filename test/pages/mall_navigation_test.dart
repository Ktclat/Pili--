import 'dart:async';

import 'package:PiliPlus/pages/mall/view.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const _entry = 'https://mall.bilibili.com/';
const _detail = 'https://mall.bilibili.com/detail.html?id=123';

Finder _toolbarButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

class _Settings extends Fake implements Box<dynamic> {
  final data = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async => data[key] = value;

  @override
  Future<void> delete(dynamic key) async => data.remove(key);
}

// The fake replaces only the native WebView. The real MallPage, buttons,
// PopScope, controller wrappers and Flutter route lifecycle remain under test.
class _Browser extends PlatformInAppWebViewController {
  _Browser(this.callbacks)
    : history = [callbacks.initialUrlRequest!.url!.toString()],
      super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'mall-test'),
      );

  PlatformInAppWebViewWidgetCreationParams callbacks;
  final List<String> history;
  Completer<bool>? historyQuery;
  Completer<void>? reloadResult;
  int reloads = 0;
  int backSteps = 0;

  InAppWebViewController get wrapper =>
      InAppWebViewController.fromPlatform(platform: this);

  void created() => callbacks.onWebViewCreated!(wrapper);

  void finish() => callbacks.onLoadStop!(wrapper, WebUri(history.last));

  void fail() => callbacks.onReceivedError!(
    wrapper,
    WebResourceRequest(url: WebUri(history.last), isForMainFrame: true),
    WebResourceError(
      type: WebResourceErrorType.HOST_LOOKUP,
      description: 'Offline',
    ),
  );

  @override
  Future<bool> canGoBack() =>
      historyQuery?.future ?? Future.value(history.length > 1);

  @override
  Future<void> goBack() async {
    backSteps++;
    if (history.length > 1) history.removeLast();
  }

  @override
  Future<void> reload() {
    reloads++;
    return reloadResult?.future ?? Future.value();
  }

  @override
  Future<void> stopLoading() async {}
}

class _WebViewPlatform extends InAppWebViewPlatform {
  final browsers = <_Browser>[];

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _PlatformView(params, browsers);
}

class _PlatformView extends PlatformInAppWebViewWidget {
  _PlatformView(super.params, this.browsers) : super.implementation();

  final List<_Browser> browsers;

  @override
  Widget build(BuildContext context) =>
      _NativeView(key: params.key, params: params, browsers: browsers);

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

class _NativeView extends StatefulWidget {
  const _NativeView({super.key, required this.params, required this.browsers});

  final PlatformInAppWebViewWidgetCreationParams params;
  final List<_Browser> browsers;

  @override
  State<_NativeView> createState() => _NativeViewState();
}

class _NativeViewState extends State<_NativeView> {
  late final _Browser browser;

  @override
  void initState() {
    super.initState();
    browser = _Browser(widget.params);
    widget.browsers.add(browser);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) browser.created();
    });
  }

  @override
  Widget build(BuildContext context) {
    browser.callbacks = widget.params;
    return const SizedBox.expand();
  }
}

void main() {
  final settings = _Settings();
  late _WebViewPlatform platform;

  setUpAll(() => GStorage.setting = settings);

  setUp(() {
    settings.data
      ..clear()
      ..['piliMinusMallEnabled'] = true;
    platform = _WebViewPlatform();
    InAppWebViewPlatform.instance = platform;
  });

  Future<_Browser> openMall(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const MallPage()),
              ),
              child: const Text('Open mall'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open mall'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final browser = platform.browsers.single..finish();
    await tester.pumpAndSettle();
    return browser;
  }

  testWidgets('refresh keeps the current detail page and browsing history', (
    tester,
  ) async {
    final browser = await openMall(tester);
    browser.history.add(_detail);

    await tester.tap(_toolbarButton('刷新'));
    await tester.pump();

    expect(platform.browsers, [browser]);
    expect(browser.reloads, 1);
    expect(browser.history, [_entry, _detail]);
    browser.finish();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('system back visits web history before leaving the mall', (
    tester,
  ) async {
    final browser = await openMall(tester);
    browser.history.add(_detail);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(browser.backSteps, 1);
    expect(browser.history, [_entry]);
    expect(find.byType(MallPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MallPage), findsNothing);
    expect(find.text('Open mall'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a late history query cannot pop a replacement browser', (
    tester,
  ) async {
    final oldBrowser = (await openMall(tester))
      ..historyQuery = Completer<bool>();
    await tester.binding.handlePopRoute();
    await tester.pump();

    await tester.tap(_toolbarButton('停用会员购'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载并启用'));
    await tester.pump();
    final replacement = platform.browsers.last..finish();
    await tester.pumpAndSettle();

    replacement.history.add(_detail);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(replacement.backSteps, 1);

    oldBrowser.historyQuery!.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(MallPage), findsOneWidget);
    expect(replacement.history, [_entry]);
    expect(oldBrowser.backSteps, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('load failure rebuilds on retry and ignores old creation', (
    tester,
  ) async {
    final oldBrowser = await openMall(tester);
    oldBrowser.fail();
    await tester.pumpAndSettle();
    expect(find.text('重新下载'), findsOneWidget);

    await tester.tap(find.text('重新下载'));
    await tester.pump();
    final replacement = platform.browsers.last;
    expect(platform.browsers.length, 2);
    expect(replacement.history, [_entry]);
    oldBrowser.created();
    replacement.finish();
    await tester.pumpAndSettle();

    await tester.tap(_toolbarButton('刷新'));
    await tester.pump();
    expect(replacement.reloads, 1);
    expect(oldBrowser.reloads, 0);
    replacement.finish();
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('late refresh failure cannot re-enable a disabled mall', (
    tester,
  ) async {
    final browser = await openMall(tester);
    browser.reloadResult = Completer<void>();
    await tester.tap(_toolbarButton('刷新'));
    await tester.pump();
    await tester.tap(_toolbarButton('停用会员购'));
    await tester.pumpAndSettle();

    browser.reloadResult!.completeError(StateError('disposed WebView'));
    browser.finish();
    await tester.pumpAndSettle();
    expect(find.text('下载并启用'), findsOneWidget);
    expect(find.text('重新下载'), findsNothing);
    expect(settings.data.containsKey('piliMinusMallEnabled'), isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
