import 'dart:io' show Platform;

import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/trusted_url.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:synchronized/synchronized.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

abstract final class LinuxCookieManager {
  static final _lock = Lock();
  static Account? _owner;
  static final _websiteData = LinuxWebViewDataManager(
    const LinuxWebViewDataManagerCreationParams(),
  );

  static Future<void> syncForPage(Uri? page) => _sync(
    writeCookies: page != null && TrustedUrl.isBilibili(page),
  );

  static Future<void> onMainAccountChanged() async {
    if (!Platform.isLinux) return;
    try {
      await _sync(writeCookies: true);
    } catch (_) {
      // The next WebView retries before it may load content.
      if (kDebugMode) debugPrint('Linux WebView account sync failed');
    }
  }

  static Future<void> _sync({required bool writeCookies}) => _lock.synchronized(
    () async {
      do {
        final account = Accounts.main;
        try {
          if (!identical(account, _owner)) {
            final result = await _websiteData.clearWebsiteDataFor(
              const WebViewDataTarget(
                scope: WebViewDataScope.domain,
                value: 'bilibili.com',
              ),
              dataTypes: const {WebViewDataType.cookies},
            );
            if (!result.isComplete) throw StateError('清理网页登录状态失败');
          }
          if (writeCookies) await _writeCookies(account);
          _owner = account;
        } catch (_) {
          _owner = null;
          rethrow;
        }
        // Switching accounts can happen while WebKit is still writing.
      } while (!identical(_owner, Accounts.main));
    },
  );

  static Future<void> _writeCookies(Account account) async {
    final store = LinuxWebViewCookieManager(
      const LinuxWebViewCookieManagerCreationParams(),
    );
    final now = DateTime.now().toUtc();
    await Future.wait(
      account.cookieJar.toList().map((cookie) async {
        final rawDomain = cookie.domain?.toLowerCase() ?? 'bilibili.com';
        final domain = rawDomain.startsWith('.')
            ? rawDomain.substring(1)
            : rawDomain;
        if (domain != 'bilibili.com' && !domain.endsWith('.bilibili.com')) {
          return;
        }
        final maxAge = cookie.maxAge;
        await store.setCookie(
          WebViewCookie(
            name: cookie.name,
            value: cookie.value,
            domain: '.$domain',
            path: cookie.path ?? '/',
            expires: maxAge == null
                ? cookie.expires
                : now.add(Duration(seconds: maxAge)),
            isSecure: true,
            isHttpOnly: cookie.httpOnly,
            sameSite: WebViewCookieSameSite.lax,
          ),
        );
      }),
    );
  }

  static Future<void> clearAllWebsiteData() => _lock.synchronized(() async {
    _owner = null;
    final result = await _websiteData.clearAllWebsiteData();
    if (!result.isComplete) {
      final errors = result.failures.values.toSet().join('; ');
      throw StateError(errors.isEmpty ? '未能清理全部网站数据' : errors);
    }
  });
}
