import 'dart:io' show Platform;

import 'package:PiliPlus/main.dart' show webViewEnvironment;
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/linux_cookie_manager.dart';
import 'package:PiliPlus/utils/trusted_url.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as web;
import 'package:synchronized/synchronized.dart';

/// Synchronizes the Bilibili domain/root cookie jar used by native account requests.
abstract final class NativeAccountCookies {
  static final _origin = web.WebUri('https://bilibili.com/');
  static const _domain = '.bilibili.com';
  static final _lock = Lock();
  static Account? _owner;

  static Future<void> onMainAccountChanged() async {
    if (Platform.isLinux) return LinuxCookieManager.onMainAccountChanged();
    try {
      await _sync(writeCookies: true);
    } catch (_) {
      // The next page must synchronize again before creating its WebView.
      if (kDebugMode) debugPrint('WebView account sync failed');
    }
  }

  static bool _isRootCookie(String? domain, String? path) =>
      (domain == null || domain == 'bilibili.com' || domain == _domain) &&
      (path == null || path == '/');

  static Future<void> syncForPage(Uri? page) => _sync(
    writeCookies: page != null && TrustedUrl.isBilibili(page),
  );

  static Future<void> _sync({required bool writeCookies}) =>
      _lock.synchronized(() async {
        final manager = web.CookieManager.instance(
          webViewEnvironment: webViewEnvironment,
        );
        Account account;
        do {
          account = Accounts.main;
          try {
            if (!identical(account, _owner)) await _clearRootCookies(manager);
            if (writeCookies) await _writeAccount(manager, account);
            _owner = account;
          } catch (_) {
            _owner = null;
            rethrow;
          }
        } while (!identical(account, Accounts.main));
      });

  static Future<void> _clearRootCookies(web.CookieManager manager) async {
    for (final cookie in await manager.getCookies(url: _origin)) {
      if (!_isRootCookie(cookie.domain, cookie.path)) continue;
      // Older Android WebViews return only names and values for this URL.
      final removed = await manager.deleteCookie(
        url: _origin,
        name: cookie.name,
        domain: cookie.domain ?? _domain,
      );
      if (!removed) throw StateError('清理网页登录状态失败');
    }
  }

  static Future<void> _writeAccount(
    web.CookieManager manager,
    Account account,
  ) async {
    for (final cookie in account.cookieJar.toList()) {
      if (!_isRootCookie(cookie.domain, cookie.path)) continue;
      final written = await manager.setCookie(
        url: _origin,
        name: cookie.name,
        value: cookie.value,
        domain: _domain,
        isSecure: true,
        isHttpOnly: cookie.httpOnly,
        expiresDate: cookie.expires?.millisecondsSinceEpoch,
        maxAge: cookie.maxAge,
        sameSite: web.HTTPCookieSameSitePolicy.LAX,
      );
      if (!written) throw StateError('同步网页登录状态失败');
    }
  }
}
