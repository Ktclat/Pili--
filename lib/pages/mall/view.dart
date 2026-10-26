import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/trusted_url.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';

/// The official H5 application is downloaded by WebView only after opting in.
/// No executable plugin, JS bridge or native payment handler is installed.
class MallPage extends StatefulWidget {
  const MallPage({super.key});
  @override
  State<MallPage> createState() => _MallPageState();
}

class _MallPageState extends State<MallPage> with WidgetsBindingObserver {
  static const _enabledKey = 'piliMinusMallEnabled';
  static const _entry = 'https://mall.bilibili.com/';
  InAppWebViewController? _controller;
  late bool _enabled = GStorage.setting.get(_enabledKey, defaultValue: false);
  bool _loading = false;
  bool _openingExternal = false;
  String? _error;
  double _progress = 0;
  int _generation = 0;
  Timer? _timeout;

  // The plugin creates distinct Dart wrappers for creation and load callbacks.
  // Their platform controller identifies the same native WebView instance.
  bool _isCurrent(InAppWebViewController controller) =>
      mounted && identical(_controller?.platform, controller.platform);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_enabled) _begin();
  }

  void _begin() {
    _timeout?.cancel();
    _loading = true;
    _error = null;
    _progress = 0;
    _timeout = Timer(const Duration(seconds: 35), () {
      if (mounted && _loading) _fail('下载超时，请检查网络后重试');
    });
  }

  void _fail(String message) {
    _timeout?.cancel();
    unawaited(_controller?.stopLoading());
    if (mounted) {
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  Future<void> _disable() async {
    if (!mounted) return;
    _timeout?.cancel();
    setState(() {
      _enabled = false;
      _loading = false;
      _controller = null;
      _error = null;
      _generation++;
    });
    await GStorage.setting.delete(_enabledKey);
  }

  void _retry() => setState(() {
    _generation++;
    _controller = null;
    _begin();
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller?.resume());
    } else {
      unawaited(_controller?.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeout?.cancel();
    _controller = null;
    super.dispose();
  }

  Future<void> _external(Uri uri) async {
    if (_openingExternal || !mounted) return;
    if (!TrustedUrl.isWebLink(uri) &&
        !const ['alipays', 'weixin'].contains(uri.scheme)) {
      return;
    }
    _openingExternal = true;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开外部应用'),
        content: Text(
          '会员购请求打开：\n${uri.scheme == 'https' || uri.scheme == 'http' ? uri.host : uri.scheme}\n请在目标应用核对订单和金额。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (open == true && mounted) await PageUtils.launchURL(uri.toString());
    _openingExternal = false;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('会员购'),
      actions: [
        if (_enabled || _loading) ...[
          IconButton(
            tooltip: '网页后退',
            onPressed: () async {
              if (await _controller?.canGoBack() == true) {
                await _controller?.goBack();
              }
            },
            icon: const Icon(Icons.arrow_back),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _retry,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '停用会员购',
            onPressed: _disable,
            icon: const Icon(Icons.power_settings_new),
          ),
        ],
      ],
    ),
    body: SafeArea(
      child: !Platform.isAndroid && !Platform.isIOS
          ? Center(
              child: FilledButton(
                onPressed: () => PageUtils.launchURL(_entry),
                child: const Text('在浏览器打开会员购'),
              ),
            )
          : !_enabled && !_loading && _error == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shopping_bag_outlined, size: 64),
                    const SizedBox(height: 16),
                    const Text('按需启用会员购', style: TextStyle(fontSize: 22)),
                    const SizedBox(height: 12),
                    const Text(
                      '首次使用需联网下载哔哩哔哩官方会员购网页组件（HTML、脚本和图片，大小由官方页面决定）。后续按系统缓存复用。\n\n未启用时不会加载会员购，退出页面后释放浏览器。订单、登录和支付由官方页面处理。',
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => setState(_begin),
                      icon: const Icon(Icons.download),
                      label: const Text('下载并启用'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_loading)
                  LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                  ),
                if (_error != null)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _retry,
                              child: const Text('重新下载'),
                            ),
                            TextButton(
                              onPressed: _disable,
                              child: const Text('返回'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: InAppWebView(
                      key: ValueKey(_generation),
                      initialUrlRequest: URLRequest(url: WebUri(_entry)),
                      initialSettings: InAppWebViewSettings(
                        userAgent: BrowserUa.mob,
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        cacheEnabled: true,
                        clearCache: false,
                        useShouldOverrideUrlLoading: true,
                        mixedContentMode:
                            MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                        allowFileAccess: false,
                        allowContentAccess: false,
                        javaScriptCanOpenWindowsAutomatically: false,
                        supportMultipleWindows: false,
                        thirdPartyCookiesEnabled: false,
                      ),
                      onWebViewCreated: (controller) =>
                          _controller = controller,
                      onProgressChanged: (controller, progress) {
                        if (_isCurrent(controller)) {
                          setState(() => _progress = progress / 100);
                        }
                      },
                      onLoadStop: (controller, url) async {
                        if (!_isCurrent(controller) ||
                            _error != null ||
                            url == null ||
                            !TrustedUrl.isBilibili(url.uriValue)) {
                          return;
                        }
                        _timeout?.cancel();
                        await GStorage.setting.put(_enabledKey, true);
                        if (_isCurrent(controller)) {
                          setState(() {
                            _enabled = true;
                            _loading = false;
                          });
                        }
                      },
                      onReceivedError: (controller, request, _) {
                        if (_isCurrent(controller) &&
                            request.isForMainFrame == true) {
                          _fail('会员购页面加载失败，请检查网络后重试');
                        }
                      },
                      onReceivedHttpError: (controller, request, response) {
                        if (_isCurrent(controller) &&
                            request.isForMainFrame == true) {
                          _fail('会员购暂时不可用（HTTP ${response.statusCode}）');
                        }
                      },
                      onReceivedServerTrustAuthRequest: (_, _) async =>
                          ServerTrustAuthResponse(
                            action: ServerTrustAuthResponseAction.CANCEL,
                          ),
                      shouldOverrideUrlLoading: (_, navigation) async {
                        final uri = navigation.request.url?.uriValue;
                        if (uri == null) return NavigationActionPolicy.CANCEL;
                        if (TrustedUrl.isBilibili(uri)) {
                          return NavigationActionPolicy.ALLOW;
                        }
                        if (navigation.isForMainFrame) {
                          unawaited(_external(uri));
                        }
                        return NavigationActionPolicy.CANCEL;
                      },
                    ),
                  ),
              ],
            ),
    ),
  );
}
