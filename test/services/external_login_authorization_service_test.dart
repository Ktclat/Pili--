import 'dart:async';

import 'package:PiliPlus/models/qr_login_authorization.dart';
import 'package:PiliPlus/services/external_login_authorization_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(ExternalLoginAuthorizationService.channelName);
  const codec = StandardMethodCodec();
  const web =
      'https://account.bilibili.com/h5/account-h5/auth/scan-web'
      '?qrcode_key=0123456789abcdef0123456789abcdef';
  const tv =
      'https://passport.bilibili.com/h5-app/passport/login/scan-pad'
      '?auth_code=9876543210abcdef9876543210abcdef';
  late ExternalLoginAuthorizationService service;
  late List<QrLoginAuthorizationRequest> opened;
  late Completer<void> closed;
  late int rejected;
  Object? next;

  Future<void> signal([String method = 'onAuthorizationAvailable']) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method)),
      null,
    );
  }

  setUp(() {
    next = null;
    rejected = 0;
    opened = [];
    closed = Completer<void>();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takeAuthorization');
      final oneShot = next;
      next = null;
      return oneShot;
    });
    service = ExternalLoginAuthorizationService(
      channel: channel,
      present: (request) {
        opened.add(request);
        return closed.future;
      },
      reject: () => rejected++,
    );
  });

  tearDown(() {
    service.dispose();
    if (!closed.isCompleted) closed.complete();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('cold and warm entry present once and keep the original age', () async {
    next = {'url': web, 'ageMs': 60000};
    final before = DateTime.now();
    await service.start();
    await service.start();
    await signal();

    expect(opened.single.kind, QrLoginAuthorizationKind.web);
    expect(service.blocksClipboard, isTrue);
    expect(
      opened.single.receivedAt
          .add(const Duration(minutes: 1))
          .microsecondsSinceEpoch,
      inInclusiveRange(
        before.microsecondsSinceEpoch,
        DateTime.now().microsecondsSinceEpoch,
      ),
    );
    next = {'url': tv, 'ageMs': 0};
    await signal();
    expect(opened, hasLength(1));
    expect(next, isNull);
    closed.complete();
    await Future<void>.delayed(Duration.zero);
    await signal();
    expect(opened, hasLength(1));
    expect(service.blocksClipboard, isFalse);

    next = {'url': tv, 'ageMs': 0};
    closed = Completer<void>();
    await signal();
    expect(opened.last.kind, QrLoginAuthorizationKind.television);
    expect(rejected, 0);
  });

  test('malformed, expired, and ordinary content never navigate', () async {
    await service.start();
    for (final invalid in [
      {'url': web, 'ageMs': -1},
      {'url': web, 'ageMs': QrLoginAuthorizationRequest.maxAge.inMilliseconds},
      {'url': web, 'ageMs': '0'},
      web,
      {'url': '', 'ageMs': 0},
      {'url': 'https://www.bilibili.com/video/BV1xx411c7mD', 'ageMs': 0},
      {'url': web.replaceFirst('account.', 'example.'), 'ageMs': 0},
    ]) {
      next = invalid;
      final previous = rejected;
      await signal();
      expect(rejected, previous + 1);
    }
    expect(opened, isEmpty);
  });

  test('retains only the first background request until resumed', () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await service.start();
    next = {'url': web, 'ageMs': 0};
    await signal();
    next = {'url': tv, 'ageMs': 0};
    await signal();
    expect(opened, isEmpty);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(opened.single.kind, QrLoginAuthorizationKind.web);
  });

  testWidgets('an expired background challenge is discarded before resume', (
    tester,
  ) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    next = {
      'url': web,
      'ageMs': QrLoginAuthorizationRequest.maxAge.inMilliseconds - 1000,
    };
    await service.start();
    await tester.pump(const Duration(seconds: 2));
    expect(rejected, 0);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(opened, isEmpty);
    expect(rejected, 1);
  });

  test('disposal during native intake prevents late navigation', () async {
    final response = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => response.future);
    final started = service.start();
    expect(service.blocksClipboard, isTrue);
    service.dispose();
    response.complete({'url': web, 'ageMs': 0});
    await started;
    expect(opened, isEmpty);
    expect(rejected, 0);
  });
}
