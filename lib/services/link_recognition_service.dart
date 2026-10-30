import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/pages/link_recognition/view.dart';
import 'package:PiliPlus/services/incoming_share_service.dart';
import 'package:PiliPlus/services/link_recognition_controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LinkRecognitionService with WidgetsBindingObserver {
  final _share = IncomingShareService();
  StreamSubscription<dynamic>? _settings;
  bool _disposed = false;
  late final _controller = LinkRecognitionController(
    allowShares: () => Pref.receiveSharedLinks,
    allowClipboard: () =>
        Pref.recognizeClipboardLinks &&
        !const [
          '/scan',
          '/scanLogin',
          '/recognizeLink',
        ].contains(Get.currentRoute) &&
        !Get.currentRoute.contains('QrLoginAuthorizationPage'),
    isForeground: () =>
        !_disposed &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    readClipboard: () async =>
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
    present: (links, source) async {
      final context = Get.overlayContext ?? Get.context;
      if (context == null || !context.mounted || _disposed) return;
      await confirmRecognizedLinks(
        context,
        links,
        title: source == LinkRecognitionSource.share ? '收到分享链接' : '剪贴板中有 B 站链接',
      );
    },
  );

  Future<void> start() async {
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    _settings = GStorage.setting.watch().listen((event) {
      if (event.key == SettingBoxKey.recognizeClipboardLinks) {
        _controller.invalidateClipboard(forget: true);
        if (Pref.recognizeClipboardLinks) _run(_controller.checkClipboard());
      }
    });
    if (Platform.isAndroid) {
      try {
        await _share.start(
          onShare: (message) {
            _run(_controller.receiveShare(message.id, message.text));
          },
        );
      } catch (_) {
        // An unavailable platform bridge must not prevent manual recognition.
      }
    }
    if (!_disposed) _run(_controller.checkClipboard());
  }

  void _run(Future<void> action) {
    // Clipboard/intent failures must not interrupt playback or startup.
    unawaited(action.catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _run(_controller.drain().then((_) => _controller.checkClipboard()));
    } else {
      _controller.invalidateClipboard();
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    unawaited(_settings?.cancel());
    unawaited(_share.dispose());
  }
}
