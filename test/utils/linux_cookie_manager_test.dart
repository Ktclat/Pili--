import 'dart:async';

import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/linux_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_linux/webview_all_linux.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final page = Uri.parse('https://www.bilibili.com:443/video');
  final calls = <MethodCall>[];
  final stored = <String, String>{};
  Completer<void>? writeStarted;
  Completer<void>? finishWrite;
  late Account previous;

  LoginAccount accountWith(List<Cookie> cookies) {
    final jar = DefaultCookieJar();
    jar.domainCookies['bilibili.com'] = {
      '/': {
        for (final cookie in cookies) cookie.name: SerializableCookie(cookie),
      },
    };
    return LoginAccount(jar, null, null);
  }

  void switchTo(Account account) =>
      Accounts.accountMode[AccountType.main.index] = account;

  setUp(() {
    previous = Accounts.main;
    calls.clear();
    stored.clear();
    writeStarted = finishWrite = null;
    messenger.setMockMethodCallHandler(LinuxWebViewController.rootChannel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'clearWebsiteDataFor') {
        expect(call.arguments['target'], {
          'scope': 'domain',
          'value': 'bilibili.com',
        });
        expect(call.arguments['dataTypes'], [0]);
        stored.clear();
      } else if (call.method == 'setCookie') {
        if (call.arguments['name'] == 'session' &&
            writeStarted != null &&
            !writeStarted!.isCompleted) {
          writeStarted!.complete();
          await finishWrite!.future;
        }
        stored[call.arguments['name']] = call.arguments['value'];
      }
      return null;
    });
  });
  tearDown(() {
    switchTo(previous);
    messenger.setMockMethodCallHandler(
      LinuxWebViewController.rootChannel,
      null,
    );
  });

  test('syncs scoped cookies to the native store before navigation', () async {
    final expiry = DateTime.utc(2030);
    switchTo(
      accountWith([
        Cookie('session', 'sample')
          ..domain = '.bilibili.com'
          ..httpOnly = true
          ..path = '/video'
          ..expires = expiry,
        Cookie('otherSite', 'sample')..domain = 'example.org',
      ]),
    );
    await LinuxCookieManager.syncForPage(page);
    final session = calls.singleWhere(
      (c) => c.method == 'setCookie' && c.arguments['name'] == 'session',
    );
    expect(stored, isNot(contains('otherSite')));
    expect(session.arguments, containsPair('domain', '.bilibili.com'));
    expect(session.arguments, containsPair('path', '/video'));
    expect(session.arguments, containsPair('isSecure', true));
    expect(session.arguments, containsPair('isHttpOnly', true));
    expect(
      session.arguments,
      containsPair('expires', expiry.millisecondsSinceEpoch),
    );
  });

  test('skips cookie writes for untrusted initial pages', () async {
    switchTo(accountWith([Cookie('session', 'first')]));
    for (final url in [
      'http://www.bilibili.com',
      'https://www.bilibili.com:444',
      'https://name@www.bilibili.com/',
      'https://bilibili.com.example.org/',
    ]) {
      await LinuxCookieManager.syncForPage(Uri.parse(url));
    }
    expect(stored, isEmpty);
  });

  test(
    'switching to a partial account removes cookies missing from its jar',
    () async {
      switchTo(accountWith([Cookie('session', 'A'), Cookie('oldOnly', 'A')]));
      await LinuxCookieManager.syncForPage(page);
      switchTo(accountWith([Cookie('session', 'B')]));
      await LinuxCookieManager.syncForPage(page);
      expect(stored['session'], 'B');
      expect(stored, isNot(contains('oldOnly')));
    },
  );

  test(
    'an in-flight write finishes before logout clears the previous account',
    () async {
      switchTo(accountWith([Cookie('session', 'A')]));
      writeStarted = Completer<void>();
      finishWrite = Completer<void>();
      final opening = LinuxCookieManager.syncForPage(page);
      await writeStarted!.future;
      switchTo(AnonymousAccount());
      final logout = LinuxCookieManager.onMainAccountChanged();
      finishWrite!.complete();
      await opening;
      expect(stored, isNot(contains('session')));
      await logout;
      expect(stored, isNot(contains('session')));
    },
  );
}
