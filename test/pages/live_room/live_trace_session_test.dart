import 'dart:async';

import 'package:PiliPlus/pages/live_room/live_trace_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a stopped request cannot restart or alter a resumed session', (
    tester,
  ) async {
    final session = LiveTraceSession(() => true);
    final pending = Completer<Duration?>();
    late CancelToken oldToken;
    var oldCalls = 0;
    session.start((token) {
      oldToken = token;
      oldCalls++;
      return pending.future;
    });
    await tester.pump(const Duration(minutes: 3));
    expect(oldCalls, 1);
    session.stop();
    expect(oldToken.isCancelled, isTrue);

    var newCalls = 0;
    session.start((_) async {
      newCalls++;
      return const Duration(minutes: 1);
    });
    pending.complete(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 59));
    expect(oldCalls, 1);
    expect(newCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(newCalls, 2);
    session.stop();
  });

  testWidgets(
    'permission is checked before the first and subsequent requests',
    (
      tester,
    ) async {
      var allowed = false;
      final session = LiveTraceSession(() => allowed);
      var calls = 0;
      Future<Duration?> send(CancelToken _) async {
        calls++;
        return const Duration(seconds: 5);
      }

      session.start(send);
      expect(calls, 0);
      allowed = true;
      session
        ..start(send)
        ..start(send);
      await tester.pump();
      expect(calls, 1);
      allowed = false;
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 1);
      allowed = true;
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 1);
      session.stop();
    },
  );
}
