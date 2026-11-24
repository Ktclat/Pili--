import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/common/widgets/route_aware_mixin.dart'
    show routeObserver;
import 'package:PiliPlus/common/widgets/selection_text.dart';
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/main.dart' show webViewEnvironment;
import 'package:PiliPlus/models/common/webview_menu_type.dart';
import 'package:PiliPlus/plugin/linux_webview.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/linux_cookie_manager.dart';
import 'package:PiliPlus/utils/native_account_cookies.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/trusted_url.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart'
    hide WebResourceResponse;

final _prefixRegex = RegExp(r'^(?!(https?://))\S+://', caseSensitive: false);

class WebviewPage extends StatefulWidget {
  const WebviewPage({super.key, this.url, this.oid, this.title});

  // note
  final int? oid;
  final String? title;
  final String? url;

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> with RouteAware {
  late String _currentUrl;
  late final String userAgent;
  late final RxString _title;
  final RxDouble _progress = 1.0.obs;
  bool _inApp = false;
  bool _off = false;

  InAppWebViewController? _webViewController;
  LinuxWebViewController? _linuxController;

  @override
  void initState() {
    super.initState();
    final parameters = Get.parameters;
    _currentUrl = (widget.url ?? parameters['url']!).http2https;
    _title = _currentUrl.obs;
    userAgent = switch (parameters['uaType']) {
      'pc' => BrowserUa.pc,
      'mob' => BrowserUa.mob,
      _ => BrowserUa.platform,
    };
    if (Get.arguments case final Map map) {
      _inApp = map['inApp'] ?? false;
      _off = map['off'] ?? false;
    }

    if (Platform.isAndroid) {
      routeObserver.subscribe(this, Get.routing.route as GetPageRoute);
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid) routeObserver.unsubscribe(this);
    _linuxController = null;
    _webViewController = null;
    super.dispose();
  }

  late Future<void> _initialCookies = NativeAccountCookies.syncForPage(
    Uri.tryParse(_currentUrl),
  );

  bool _isPop = false;
  @override
  void didPop() {
    setState(() {
      _webViewController = null;
      _isPop = true;
    });
    super.didPop();
  }

  List<Widget> get _actions {
    return [
      PopupMenuButton<WebviewMenuItem>(
        onSelected: _handleMenuItem,
        itemBuilder: (context) => <PopupMenuEntry<WebviewMenuItem>>[
          ...WebviewMenuItem.values
              .take(WebviewMenuItem.values.length - 1)
              .map(
                (item) => PopupMenuItem(value: item, child: Text(item.title)),
              ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: WebviewMenuItem.goBack,
            child: Text(
              WebviewMenuItem.goBack.title,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> get _linuxActions => [
    _LinuxContextMenuButton(onSelected: _handleMenuItem),
  ];

  Future<void> _handleMenuItem(WebviewMenuItem item) async {
    switch (item) {
      case WebviewMenuItem.refresh:
        if (Platform.isLinux) {
          _linuxController?.reload();
        } else {
          _webViewController?.reload();
        }
        break;
      case WebviewMenuItem.copy:
        if (Platform.isLinux) {
          Utils.copyText(_currentUrl);
        } else {
          WebUri? uri = await _webViewController?.getUrl();
          if (uri != null) {
            Utils.copyText(uri.toString());
          }
        }
        break;
      case WebviewMenuItem.openInBrowser:
        if (Platform.isLinux) {
          PageUtils.launchURL(_currentUrl);
        } else {
          WebUri? uri = await _webViewController?.getUrl();
          if (uri != null) {
            PageUtils.launchURL(uri.toString());
          }
        }
        break;
      case WebviewMenuItem.clearCache:
        try {
          if (Platform.isLinux) {
            await LinuxCookieManager.clearAllWebsiteData();
            _linuxController?.reload();
            SmartDialog.showToast('已清理缓存并刷新', alignment: Alignment.topCenter);
          } else {
            await InAppWebViewController.clearAllCache();
            await _webViewController?.clearHistory();
            SmartDialog.showToast('已清理');
          }
        } catch (e) {
          SmartDialog.showToast(e.toString());
        }
        break;
      case WebviewMenuItem.goBack:
        if (Platform.isLinux) {
          _linuxController?.goBack();
        } else {
          if (await _webViewController?.canGoBack() == true) {
            _webViewController?.goBack();
          } else {
            Get.back();
          }
        }
        break;
      case WebviewMenuItem.resetCookie:
        if (Platform.isLinux) {
          try {
            await LinuxCookieManager.syncForPage(Uri.tryParse(_currentUrl));
            if (!mounted) return;
            await _linuxController?.reload();
            SmartDialog.showToast('正在刷新网页', alignment: Alignment.topCenter);
          } catch (_) {
            if (mounted) SmartDialog.showToast('网页登录状态同步失败');
          }
        } else {
          try {
            final url = await _webViewController?.getUrl();
            await NativeAccountCookies.syncForPage(url?.uriValue);
            if (mounted) await _webViewController?.reload();
          } catch (_) {
            if (mounted) SmartDialog.showToast('网页登录状态同步失败');
          }
        }
        break;
    }
  }

  List<WebViewUserScript> _getLinuxUserScripts() {
    return [
      if (TrustedUrl.isBilibiliNote(Uri.tryParse(_currentUrl)))
        const WebViewUserScript(
          source: """
document.addEventListener('click', function(e) {
  var finishBtn = e.target && e.target.closest ? e.target.closest('.finish-btn') : null;
  if (finishBtn) {
    window.PiliPlus.postMessage('finishButtonClicked');
    return;
  }
  var infoBar = e.target && e.target.closest ? e.target.closest('.info-bar') : null;
  if (infoBar) {
    window.PiliPlus.postMessage('infoBarClicked');
    return;
  }
}, true);
""",
        ),
      if (_currentUrl.startsWith('https://live.bilibili.com'))
        const WebViewUserScript(
          source: """
(function() {
  function injectStyle() {
    if (document.getElementById('pili-live-style')) return;
    var s = document.createElement('style');
    s.id = 'pili-live-style';
    s.textContent = 'div.open-app-btn.bili-btn-warp {display:none !important;} #app__display-area > div.control-panel {display:none !important;}';
    (document.head || document.documentElement).appendChild(s);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectStyle);
  } else {
    injectStyle();
  }
})();
""",
        ),
    ];
  }

  Widget _buildLinuxView(BuildContext context) {
    return Scaffold(
      appBar: widget.url != null
          ? null
          : AppBar(
              title: Obx(
                () => Text(
                  _title.value.isNotEmpty ? _title.value : _currentUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: Size.zero,
                child: Obx(
                  () => _progress.value < 1
                      ? LinearProgressIndicator(value: _progress.value)
                      : const SizedBox.shrink(),
                ),
              ),
              actions: _linuxActions,
            ),
      body: LinuxWebview(
        initialUrl: _currentUrl,
        userAgent: userAgent,
        userScripts: _getLinuxUserScripts(),
        onWebViewCreated: (ctr) async {
          _linuxController = ctr;
          await LinuxCookieManager.syncForPage(Uri.tryParse(_currentUrl));
        },
        onUrlChanged: (u) {
          final previousUrl = _currentUrl;
          _currentUrl = u;
          if (_title.value.isEmpty || _title.value == previousUrl) {
            _title.value = u;
          }
        },
        onTitleChanged: (t) {
          _title.value = t;
        },
        onProgress: (p) {
          _progress.value = p;
        },
        onWebMessageReceived: (message) {
          final source = Uri.tryParse(message.sourceUrl ?? '');
          if (!mounted ||
              !TrustedUrl.isCurrentNoteMessage(
                source: source,
                origin: message.sourceOrigin,
                mainFrame: message.isMainFrame,
                current: Uri.tryParse(_currentUrl),
              )) {
            return;
          }
          if (message.message == 'finishButtonClicked') {
            Get.back();
          } else if (message.message == 'infoBarClicked') {
            final id = TrustedUrl.noteVideoId(source);
            if (id != null) {
              PiliScheme.videoPush(id, null);
            }
          }
        },
        onNavigationRequest: (request) async {
          final url = request.url;
          final uri = Uri.tryParse(url);
          if (!request.isMainFrame ||
              uri == null ||
              const {
                'http',
                'https',
                'about',
                'data',
                'blob',
              }.contains(uri.scheme)) {
            return NavigationDecision.navigate;
          }
          if (!_inApp) {
            final handled = await PiliScheme.routePush(
              uri,
              selfHandle: true,
              off: _off,
            );
            if (handled) return NavigationDecision.prevent;
          }
          if (mounted) PageUtils.launchURL(url);
          return NavigationDecision.prevent;
        },
      ),
    );
  }

  Widget _afterCookieSync({required Widget child}) => FutureBuilder<void>(
    future: _initialCookies,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(() {
              _initialCookies = NativeAccountCookies.syncForPage(
                Uri.tryParse(_currentUrl),
              );
            }),
            child: const Text('网页登录状态同步失败，点此重试'),
          ),
        );
      }
      return SafeArea(child: child);
    },
  );

  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux) {
      return _buildLinuxView(context);
    }
    return Scaffold(
      appBar: widget.url != null
          ? null
          : AppBar(
              title: Obx(
                () => Text(
                  _title.value.isNotEmpty ? _title.value : _currentUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: Size.zero,
                child: Obx(
                  () => _progress.value < 1
                      ? LinearProgressIndicator(value: _progress.value)
                      : const SizedBox.shrink(),
                ),
              ),
              actions: _isPop ? null : _actions,
            ),
      body: _isPop
          ? null
          : _afterCookieSync(
              child: InAppWebView(
                webViewEnvironment: webViewEnvironment,
                initialSettings: InAppWebViewSettings(
                  clearCache: false,
                  javaScriptEnabled: true,
                  forceDark: ForceDark.AUTO,
                  useHybridComposition: true,
                  algorithmicDarkeningAllowed: true,
                  useShouldOverrideUrlLoading: true,
                  userAgent: userAgent,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                  allowFileAccess: false,
                  allowContentAccess: false,
                ),
                initialUrlRequest: URLRequest(
                  url: WebUri.uri(Uri.tryParse(_currentUrl) ?? Uri()),
                ),
                onWebViewCreated: (InAppWebViewController controller) {
                  _webViewController = controller
                    ..addJavaScriptHandler(
                      handlerName: 'finishButtonClicked',
                      callback: (args) async {
                        final uri = (await controller.getUrl())?.uriValue;
                        if (mounted && TrustedUrl.isBilibiliNote(uri)) {
                          Get.back();
                        }
                      },
                    )
                    ..addJavaScriptHandler(
                      handlerName: 'infoBarClicked',
                      callback: (args) async {
                        final uri = (await controller.getUrl())?.uriValue;
                        final id = TrustedUrl.noteVideoId(uri);
                        if (mounted && id != null) {
                          PiliScheme.videoPush(id, null);
                        }
                      },
                    );
                },
                onProgressChanged: (controller, progress) {
                  _progress.value = progress / 100;
                },
                onTitleChanged: (controller, title) {
                  _title.value = title ?? '';
                },
                onCloseWindow: (controller) => Get.back(),
                onLoadStop: (controller, uri) {
                  final url = uri.toString();
                  if (TrustedUrl.isBilibiliNote(uri?.uriValue)) {
                    controller
                      ..evaluateJavascript(
                        source: """
document.querySelector('.finish-btn').addEventListener('click', function() {
    window.flutter_inappwebview.callHandler('finishButtonClicked');
});
""",
                      )
                      ..evaluateJavascript(
                        source: """
document.querySelector('.info-bar').addEventListener('click', function() {
    window.flutter_inappwebview.callHandler('infoBarClicked');
});
""",
                      );
                  } else if (url.startsWith('https://live.bilibili.com')) {
                    controller.evaluateJavascript(
                      source: '''
document.styleSheets[0].insertRule('div.open-app-btn.bili-btn-warp {display:none;}', 0);
document.styleSheets[0].insertRule('#app__display-area > div.control-panel {display:none;}', 0);
                  ''',
                    );
                  }
                  // _webViewController?.evaluateJavascript(
                  //   source: '''
                  //     document.querySelector('#internationalHeader').remove();
                  //     document.querySelector('#message-navbar').remove();
                  //   ''',
                  // );
                },
                onDownloadStartRequest: Platform.isAndroid
                    ? (controller, request) {
                        showDialog(
                          context: context,
                          builder: (context) {
                            String suggestedFilename = request.suggestedFilename
                                .toString();
                            final fileSize = request.contentLength.formatSize;
                            try {
                              suggestedFilename = Uri.decodeComponent(
                                suggestedFilename,
                              );
                            } catch (e) {
                              if (kDebugMode) debugPrint(e.toString());
                            }
                            final url = request.url.toString();
                            return AlertDialog(
                              title: Text(
                                '下载文件: $suggestedFilename ?',
                                style: const TextStyle(fontSize: 18),
                              ),
                              content: SelectionText(url),
                              actions: [
                                TextButton(
                                  onPressed: Get.back,
                                  child: Text(
                                    '取消',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Get.back();
                                    PageUtils.launchURL(url);
                                  },
                                  child: Text('确定 ($fileSize)'),
                                ),
                              ],
                            );
                          },
                        );
                        _progress.value = 1;
                      }
                    : null,
                shouldInterceptAjaxRequest: (controller, ajaxRequest) async {
                  String url = ajaxRequest.url.toString();
                  if (url.startsWith('//api.bilibili.com/x/note/add') &&
                      widget.title != null) {
                    return ajaxRequest
                      ..data = ajaxRequest.data.toString().replaceFirst(
                        '&title=--&',
                        '&title=${widget.title}&',
                      );
                  }
                  return null;
                },
                shouldInterceptRequest: (controller, request) async {
                  String url = request.url.toString();
                  if (url.startsWith(
                    'https://passport.bilibili.com/x/passport-login/web',
                  )) {
                    _progress.value = 1;
                    return WebResourceResponse();
                  }
                  return null;
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  if (!_inApp) {
                    final hasMatch = await PiliScheme.routePush(
                      navigationAction.request.url?.uriValue ?? Uri(),
                      selfHandle: true,
                      off: _off,
                    );
                    // if (kDebugMode) debugPrint('webview: [$url], [$hasMatch]');
                    if (hasMatch) {
                      _progress.value = 1;
                      return .CANCEL;
                    }
                  }
                  final url = navigationAction.request.url.toString();
                  if (_prefixRegex.hasMatch(url)) {
                    if (context.mounted) {
                      final snackBar = SnackBar(
                        persist: false,
                        showCloseIcon: true,
                        content: const Text('当前网页将要打开外部链接，是否打开'),
                        action: SnackBarAction(
                          label: '打开',
                          onPressed: () => PageUtils.launchURL(url),
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(snackBar);
                    }
                    _progress.value = 1;
                    return .CANCEL;
                  }

                  return .ALLOW;
                },
              ),
            ),
    );
  }
}

/// Opens a GTK menu above the native WebView.
class _LinuxContextMenuButton extends StatefulWidget {
  const _LinuxContextMenuButton({required this.onSelected});

  final ValueChanged<WebviewMenuItem> onSelected;

  @override
  State<_LinuxContextMenuButton> createState() =>
      _LinuxContextMenuButtonState();
}

class _LinuxContextMenuButtonState extends State<_LinuxContextMenuButton> {
  static const _channel = MethodChannel(
    'com.example.piliplus/linux_context_menu',
  );
  static int _nextRequestId = 0;
  int? _requestId;

  Future<void> _show() async {
    if (_requestId != null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    RenderObject? ancestor = box;
    while (ancestor != null && ancestor is! RenderView) {
      ancestor = ancestor.parent;
    }
    if (ancestor is! RenderView || ancestor.child == null) return;

    // Include the app's UI scaling, excluding the display's device pixel ratio.
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(ancestor.child),
      Offset.zero & box.size,
    );
    final scale =
        ancestor.configuration.devicePixelRatio /
        ancestor.flutterView.devicePixelRatio;
    final entries = <WebviewMenuItem?>[
      ...WebviewMenuItem.values.take(WebviewMenuItem.values.length - 1),
      null,
      WebviewMenuItem.goBack,
    ];
    final requestId = ++_nextRequestId;
    _requestId = requestId;
    final int? index;
    try {
      index = await _channel.invokeMethod<int>('show', {
        'requestId': requestId,
        'items': entries.map((entry) => entry?.title).toList(),
        'x': rect.left * scale,
        'y': rect.top * scale,
        'width': rect.width * scale,
        'height': rect.height * scale,
      });
    } catch (error) {
      debugPrint('LinuxContextMenu.show failed: $error');
      return;
    } finally {
      _requestId = null;
    }
    if (!mounted) return;
    final value = index != null && index >= 0 && index < entries.length
        ? entries[index]
        : null;
    if (value != null) widget.onSelected(value);
  }

  @override
  void dispose() {
    if (_requestId case final requestId?) {
      unawaited(
        _channel
            .invokeMethod<void>('dismiss', {'requestId': requestId})
            .catchError((Object error) {
              debugPrint('LinuxContextMenu dismiss failed: $error');
            }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.more_vert),
    tooltip: MaterialLocalizations.of(context).showMenuTooltip,
    onPressed: _show,
  );
}
