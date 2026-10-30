import 'package:PiliPlus/utils/bili_link_recognition.dart';

enum LinkRecognitionSource { share, clipboard, manual }

/// Coordinates external input without persisting shared or clipboard text.
class LinkRecognitionController {
  LinkRecognitionController({
    required this.allowShares,
    required this.allowClipboard,
    required this.isForeground,
    required this.readClipboard,
    required this.present,
  });

  final bool Function() allowShares;
  final bool Function() allowClipboard;
  final bool Function() isForeground;
  final Future<String?> Function() readClipboard;
  final Future<void> Function(List<Uri>, LinkRecognitionSource) present;
  final _shares = <String>[];
  final _seenShareIds = <String>{};
  String? _lastClipboard;
  bool _reading = false;
  bool _readAgain = false;
  bool _presenting = false;
  bool _disposed = false;
  int _clipboardGeneration = 0;

  void invalidateClipboard({bool forget = false}) {
    _clipboardGeneration++;
    if (forget) _lastClipboard = null;
  }

  Future<void> receiveShare(String id, String text) async {
    if (_disposed || !allowShares() || !_seenShareIds.add(id)) return;
    if (_seenShareIds.length > 64) _seenShareIds.remove(_seenShareIds.first);
    if (text.length > BiliLinkRecognition.maxTextLength) return;
    _clipboardGeneration++;
    if (_shares.length < 4) _shares.add(text);
    await drain();
  }

  Future<void> drain() async {
    if (_disposed || _presenting || !isForeground()) return;
    _presenting = true;
    try {
      while (!_disposed && isForeground() && _shares.isNotEmpty) {
        final text = _shares.removeAt(0);
        if (!allowShares()) continue;
        final links = BiliLinkRecognition.parse(text);
        if (links.isNotEmpty) await present(links, LinkRecognitionSource.share);
      }
    } finally {
      _presenting = false;
    }
  }

  Future<void> checkClipboard() async {
    if (_disposed ||
        _presenting ||
        _shares.isNotEmpty ||
        !allowClipboard() ||
        !isForeground()) {
      return;
    }
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    final generation = _clipboardGeneration;
    try {
      final text = await readClipboard();
      if (_disposed ||
          generation != _clipboardGeneration ||
          !allowClipboard() ||
          !isForeground() ||
          _presenting ||
          _shares.isNotEmpty ||
          text == null ||
          text == _lastClipboard) {
        return;
      }
      _lastClipboard = text.length <= BiliLinkRecognition.maxTextLength
          ? text
          : null;
      final links = BiliLinkRecognition.parse(text);
      if (links.isNotEmpty) {
        _presenting = true;
        try {
          await present(links, LinkRecognitionSource.clipboard);
        } finally {
          _presenting = false;
        }
      }
    } finally {
      _reading = false;
      await drain();
      if (_readAgain) {
        _readAgain = false;
        await checkClipboard();
      }
    }
  }

  void dispose() {
    _disposed = true;
    _shares.clear();
    _lastClipboard = null;
    _seenShareIds.clear();
  }
}
