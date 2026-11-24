import 'dart:async';

import 'package:PiliPlus/models/qr_login_authorization.dart';
import 'package:PiliPlus/pages/scan/authorization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// Receives one-shot Android VIEW requests on a channel separate from sharing.
class ExternalLoginAuthorizationService with WidgetsBindingObserver {
  ExternalLoginAuthorizationService({
    this._channel = const MethodChannel(channelName),
    this._present = _openPage,
    this._reject = _invalidLink,
  });

  static const channelName =
      'io.github.ktclat.piliminus/external_login_authorization';
  final MethodChannel _channel;
  final Future<void> Function(QrLoginAuthorizationRequest) _present;
  final void Function() _reject;
  Future<void>? _startup;
  QrLoginAuthorizationRequest? _pending;
  Timer? _pendingExpiry;
  int _activeReads = 0;
  bool _invalid = false;
  bool _presenting = false;
  bool _disposed = false;

  static Future<void> _openPage(QrLoginAuthorizationRequest request) async {
    await Get.to<bool>(
      () => QrLoginAuthorizationPage(request: request, fromExternalApp: true),
      routeName: '/QrLoginAuthorizationPage',
    );
  }

  static void _invalidLink() {
    SmartDialog.showToast('无法识别或登录请求已过期，请返回发起登录的应用重新获取。');
  }

  bool get _busy => _presenting || QrLoginAuthorizationPage.isOpen;

  bool get blocksClipboard =>
      _activeReads > 0 || _pending != null || _invalid || _busy;

  Future<void> start() {
    if (_disposed) return Future.value();
    return _startup ??= _start();
  }

  Future<void> _start() {
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAuthorizationAvailable') await _take();
    });
    return _take();
  }

  Future<void> _take() async {
    // Consume even while busy: another challenge must never replace the one
    // being reviewed or appear as a queued prompt after the user closes it.
    final wasBusy = _busy;
    Object? payload;
    _activeReads++;
    try {
      payload = await _channel.invokeMethod<Object?>('takeAuthorization');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    } finally {
      _activeReads--;
    }
    if (_disposed ||
        payload == null ||
        wasBusy ||
        _busy ||
        _pending != null ||
        _invalid) {
      return;
    }
    if (payload case {'url': final String url, 'ageMs': final int age}) {
      if (age >= 0 && age < QrLoginAuthorizationRequest.maxAge.inMilliseconds) {
        _pending = QrLoginAuthorizationRequest.parse(
          url,
          now: DateTime.now().subtract(Duration(milliseconds: age)),
        );
      }
    }
    _invalid = _pending == null;
    if (_pending case final request?) {
      final expires = request.receivedAt.add(
        QrLoginAuthorizationRequest.maxAge,
      );
      _pendingExpiry = Timer(expires.difference(DateTime.now()), () {
        _pending = null;
        _invalid = true;
        _showIfResumed();
      });
    }
    _showIfResumed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _showIfResumed();
  }

  void _showIfResumed() {
    if (_disposed ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final request = _pending;
    final invalid = _invalid;
    _pendingExpiry?.cancel();
    _pendingExpiry = null;
    _pending = null;
    _invalid = false;
    if (_busy) return;
    if (invalid || (request != null && request.isExpired())) {
      _reject();
    } else if (request != null) {
      unawaited(_show(request));
    }
  }

  Future<void> _show(QrLoginAuthorizationRequest request) async {
    _presenting = true;
    try {
      await _present(request);
    } catch (_) {
      if (!_disposed) _reject();
    } finally {
      _presenting = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pendingExpiry?.cancel();
    _pending = null;
    _invalid = false;
    if (_startup != null) {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
  }
}
