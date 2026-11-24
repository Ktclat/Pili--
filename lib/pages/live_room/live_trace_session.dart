import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

/// Schedules the next heartbeat only after the current server response.
class LiveTraceSession {
  LiveTraceSession(this.isAllowed);

  final bool Function() isAllowed;
  CancelToken? _token;
  Timer? _timer;

  void start(Future<Duration?> Function(CancelToken token) send) {
    if (_token != null || !isAllowed()) return;
    final token = _token = CancelToken();

    Future<void> tick() async {
      Duration? delay;
      try {
        if (isAllowed()) delay = await send(token);
      } finally {
        if (identical(_token, token)) {
          if (!isAllowed() || delay == null || delay <= Duration.zero) {
            stop();
          } else {
            _timer = Timer(delay, tick);
          }
        }
      }
    }

    unawaited(tick());
  }

  void stop() {
    _token?.cancel();
    _token = null;
    _timer?.cancel();
    _timer = null;
  }
}
