import 'dart:async';

import 'package:PiliPlus/services/incoming_share_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(IncomingShareService.channelName);
  const codec = StandardMethodCodec();
  late IncomingShareService service;

  Future<void> emit(
    Object? arguments, {
    String method = 'onShareReceived',
  }) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      null,
    );
  }

  setUp(() {
    service = IncomingShareService(channel: channel);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() async {
    await service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('cold launch drains pending shares and consumes each once', () async {
    final received = <IncomingShareMessage>[];
    final pending = <Object?>[
      {
        'id': 'cold-one',
        'text': '标题 https://www.bilibili.com/video/BV1xx411c7mD',
      },
      {'id': 'cold-two', 'text': 'https://b23.tv/example'},
      null,
    ];
    var requests = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getInitialShare');
      return pending[requests++];
    });

    await service.start(onShare: received.add);
    await service.start(onShare: received.add);

    expect(requests, 3);
    expect(received.map((message) => message.id), ['cold-one', 'cold-two']);
    expect(received.first.text, contains('https://www.bilibili.com/video/'));
  });

  test('overlapping initial response and hot event do not replay', () async {
    final received = <IncomingShareMessage>[];
    final response = Completer<Object?>();
    var requests = 0;
    messenger.setMockMethodCallHandler(channel, (_) {
      return requests++ == 0 ? response.future : Future<Object?>.value();
    });
    final startup = service.start(onShare: received.add);
    const payload = {'id': 'overlap-one', 'text': 'BV1xx411c7mD'};

    await emit(payload);
    response.complete(payload);
    await startup;
    await emit(payload);

    expect(received.map((message) => message.id), ['overlap-one']);
  });

  test('new explicit shares can contain the same text', () async {
    final received = <IncomingShareMessage>[];
    await service.start(onShare: received.add);

    await emit({'id': 'warm-one', 'text': ' https://b23.tv/example '});
    await emit({'id': 'warm-one', 'text': 'https://b23.tv/example'});
    await emit({'id': 'warm-two', 'text': 'https://b23.tv/example'});

    expect(received.map((message) => message.id), ['warm-one', 'warm-two']);
    expect(received.first.text, 'https://b23.tv/example');
  });

  test(
    'malformed, empty, oversized and unrelated events are ignored',
    () async {
      final received = <IncomingShareMessage>[];
      await service.start(onShare: received.add);
      final invalid = <Object?>[
        null,
        'https://b23.tv/example',
        {'id': 'empty', 'text': '   '},
        {'id': '', 'text': 'BV1xx411c7mD'},
        {'id': 'bad id', 'text': 'BV1xx411c7mD'},
        {'id': 'nul', 'text': 'BV1xx411c7mD\u0000'},
        {'id': 1, 'text': 'BV1xx411c7mD'},
        {'id': 'not-string', 'text': <String>[]},
        {
          'id': 'oversized',
          'text': 'x' * (IncomingShareService.maxTextLength + 1),
        },
      ];
      for (final payload in invalid) {
        await emit(payload);
      }
      await emit({'id': 'unrelated', 'text': 'BV1xx411c7mD'}, method: 'other');
      await emit({'id': 'valid-after-invalid', 'text': 'BV1xx411c7mD'});

      expect(received.map((message) => message.id), ['valid-after-invalid']);
    },
  );

  test('disposed services ignore late cold responses and hot shares', () async {
    final received = <IncomingShareMessage>[];
    final response = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => response.future);
    final startup = service.start(onShare: received.add);

    await service.dispose();
    response.complete({'id': 'late-cold', 'text': 'BV1xx411c7mD'});
    await startup;
    await emit({'id': 'late-hot', 'text': 'BV1xx411c7mD'});

    expect(received, isEmpty);
    expect(() => service.start(onShare: received.add), throwsStateError);
  });

  test(
    'replacing a service on the same engine does not replay an ID',
    () async {
      final first = <IncomingShareMessage>[];
      await service.start(onShare: first.add);
      const payload = {'id': 'reattached-one', 'text': 'BV1xx411c7mD'};
      await emit(payload);
      await service.dispose();
      service = IncomingShareService(channel: channel);
      final second = <IncomingShareMessage>[];
      await service.start(onShare: second.add);
      await emit(payload);

      expect(first, hasLength(1));
      expect(second, isEmpty);
    },
  );

  test('an unavailable native bridge does not prevent startup', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) => throw MissingPluginException(),
    );
    await service.start(onShare: (_) => fail('No share should be delivered'));
  });

  test(
    'a callback failure is acknowledged without replaying its text',
    () async {
      var attempts = 0;
      await service.start(
        onShare: (_) {
          attempts++;
          throw StateError('UI unavailable');
        },
      );
      const payload = {'id': 'failed-callback', 'text': 'BV1xx411c7mD'};
      await emit(payload);
      await emit(payload);
      await emit({'id': 'after-failed-callback', 'text': 'BV1xx411c7mD'});

      expect(attempts, 2);
    },
  );
}
