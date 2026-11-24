import 'dart:async';

import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/native_account_cookies.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/services.dart';
// Exercise the Android implementation already pinned by dependency_overrides.
// ignore: depend_on_referenced_packages
import 'package:flutter_inappwebview_android/flutter_inappwebview_android.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidInAppWebViewPlatform.registerWith();
  const channel = MethodChannel(
    'com.pichillilorenzo/flutter_inappwebview_cookiemanager',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final page = Uri.parse('https://www.bilibili.com/video/BV17x411w7KC');
  final stored = <String, String>{};
  final calls = <MethodCall>[];
  late Account original;
  Completer<void>? entered;
  Completer<void>? release;
  bool rejectDelete = false;

  LoginAccount account(Map<String, String> cookies) {
    final jar = DefaultCookieJar();
    jar.domainCookies['bilibili.com'] = {
      '/': {
        for (final entry in {
          'buvid3': 'device-${cookies['session']}',
          ...cookies,
        }.entries)
          entry.key: SerializableCookie(
            Cookie(entry.key, entry.value)..setBiliDomain(),
          ),
      },
    };
    return LoginAccount(jar, null, null);
  }

  void select(Account owner) =>
      Accounts.accountMode[AccountType.main.index] = owner;

  setUp(() {
    original = Accounts.main;
    calls.clear();
    stored.clear();
    entered = release = null;
    rejectDelete = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = call.arguments as Map;
      expect(args['url'], 'https://bilibili.com/');
      switch (call.method) {
        case 'getCookies':
          return [
            // Older Android WebViews return only names and values.
            for (final cookie in stored.entries)
              {'name': cookie.key, 'value': cookie.value},
            {
              'name': 'external',
              'value': 'other-site',
              'domain': 'example.org',
            },
          ];
        case 'deleteCookie':
          expect(args['domain'], '.bilibili.com');
          expect(args['path'], '/');
          expect(args['name'], isNot('external'));
          if (rejectDelete) return false;
          stored.remove(args['name']);
          return true;
        case 'setCookie':
          expect(args['domain'], '.bilibili.com');
          expect(args['path'], '/');
          expect(args['isSecure'], isTrue);
          if (args['value'] == 'A' &&
              entered != null &&
              !entered!.isCompleted) {
            entered!.complete();
            await release!.future;
          }
          stored[args['name'] as String] = args['value'] as String;
          return true;
      }
      fail('Unexpected cookie operation: ${call.method}');
    });
  });
  tearDown(() {
    select(original);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'new and restored sessions remove only old Bilibili root cookies',
    () async {
      stored['legacy'] = 'before restart';
      select(account({'session': 'A', 'onlyA': 'old'}));
      await NativeAccountCookies.syncForPage(page);
      expect(stored, {'buvid3': 'device-A', 'session': 'A', 'onlyA': 'old'});
      select(account({'session': 'B'}));
      await NativeAccountCookies.syncForPage(page);
      expect(stored, {'buvid3': 'device-B', 'session': 'B'});
      final guest = AnonymousAccount();
      select(guest);
      await NativeAccountCookies.syncForPage(page);
      expect(stored, guest.cookieJar.toJson());
      expect(stored, isNot(contains('session')));
    },
  );

  test('a slow native write cannot restore the previous account', () async {
    select(account({'session': 'A'}));
    entered = Completer<void>();
    release = Completer<void>();
    final opening = NativeAccountCookies.syncForPage(page);
    await entered!.future;
    select(account({'session': 'B'}));
    final refreshing = NativeAccountCookies.syncForPage(page);
    release!.complete();
    await opening;
    final atOpen = Map.of(stored);
    await refreshing;
    expect(atOpen, {'buvid3': 'device-B', 'session': 'B'});
    expect(stored, {'buvid3': 'device-B', 'session': 'B'});
  });

  test('refuses a failed native deletion and retries before loading', () async {
    select(account({'session': 'B'}));
    stored['old'] = 'old';
    rejectDelete = true;
    await expectLater(NativeAccountCookies.syncForPage(page), throwsStateError);
    expect(stored, {'old': 'old'});
    rejectDelete = false;
    await NativeAccountCookies.syncForPage(page);
    expect(stored, {'buvid3': 'device-B', 'session': 'B'});
  });

  test(
    'an external or nonstandard origin cannot request an account cookie write',
    () async {
      select(account({'session': 'B'}));
      for (final source in [
        'https://example.org',
        'http://bilibili.com',
        'https://bilibili.com:8443',
      ]) {
        await NativeAccountCookies.syncForPage(Uri.parse(source));
      }
      expect(calls.map((c) => c.method), isNot(contains('setCookie')));
      expect(stored, isEmpty);
    },
  );
}
