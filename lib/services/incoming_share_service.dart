import 'package:flutter/services.dart';

/// An Android text share. This is untrusted input, not a navigation command.
class IncomingShareMessage {
  const IncomingShareMessage({required this.id, required this.text});

  final String id;
  final String text;
}

/// Receives bounded, in-memory text shares without reading the clipboard or
/// navigating. The caller applies its preferences, validates links and asks the
/// user before opening anything or authorizing a login.
class IncomingShareService {
  IncomingShareService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'io.github.ktclat.piliminus/incoming_share';
  static const maxTextLength = 8192;
  static const _maxRememberedIds = 256;
  static const _maxInitialMessages = 32;

  // IDs only, so replacing the service on the same engine does not replay an
  // already delivered share. No text is retained in this process-wide set.
  static final _seenIds = <String>{};

  final MethodChannel _channel;
  void Function(IncomingShareMessage)? _onShare;
  Future<void>? _startFuture;
  bool _disposed = false;

  Future<void> start({
    required void Function(IncomingShareMessage) onShare,
  }) {
    if (_disposed) throw StateError('Incoming share service is disposed');
    _onShare = onShare;
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    // Install first: a warm share can arrive while the initial queue is read.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShareReceived') _accept(call.arguments);
    });
    try {
      for (var index = 0; index < _maxInitialMessages && !_disposed; index++) {
        final payload = await _channel.invokeMethod<Object?>('getInitialShare');
        if (payload == null) break;
        _accept(payload);
      }
    } on MissingPluginException {
      // Optional on other platforms and older Android hosts.
    } on PlatformException {
      // Sharing must not prevent the rest of the application from starting.
    }
  }

  void _accept(Object? payload) {
    if (_disposed || payload is! Map) return;
    final id = payload['id'];
    final raw = payload['text'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        id.contains(RegExp(r'\s|\x00')) ||
        raw is! String ||
        raw.length > maxTextLength ||
        raw.contains('\u0000')) {
      return;
    }
    final text = raw.trim();
    if (text.isEmpty || !_seenIds.add(id)) return;
    while (_seenIds.length > _maxRememberedIds) {
      _seenIds.remove(_seenIds.first);
    }
    try {
      _onShare?.call(IncomingShareMessage(id: id, text: text));
    } catch (_) {
      // A UI callback failure must not ask Android to replay the same share or
      // serialize an exception containing its text back across the channel.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _onShare = null;
    _channel.setMethodCallHandler(null);
  }
}
