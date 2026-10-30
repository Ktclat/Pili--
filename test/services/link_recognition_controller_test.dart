import 'dart:async';

import 'package:PiliPlus/services/link_recognition_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = 'https://www.bilibili.com/video/BV1xx411c7mD';

class _Harness {
  bool shares = true;
  bool clipboard = false;
  bool foreground = true;
  int readCalls = 0;
  final shown = <(List<Uri>, LinkRecognitionSource)>[];
  Future<String?> Function() read = () async => _video;
  Future<void> Function(List<Uri>, LinkRecognitionSource)? onPresent;
  late final controller = LinkRecognitionController(
    allowShares: () => shares,
    allowClipboard: () => clipboard,
    isForeground: () => foreground,
    readClipboard: () {
      readCalls++;
      return read();
    },
    present: (links, source) async {
      shown.add((List.of(links), source));
      await onPresent?.call(links, source);
    },
  );
}

Future<void> _nextTurn() => Future<void>.delayed(Duration.zero);

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.controller.dispose());

  test(
    'disabled automatic clipboard recognition never reads the clipboard',
    () async {
      await h.controller.checkClipboard();
      await h.controller.checkClipboard();
      expect(h.readCalls, 0);
      expect(h.shown, isEmpty);
    },
  );

  test(
    'background state never reads the clipboard even when opted in',
    () async {
      h
        ..clipboard = true
        ..foreground = false;
      await h.controller.checkClipboard();
      expect(h.readCalls, 0);
    },
  );

  test(
    'opted-in clipboard recognition asks once for unchanged content',
    () async {
      h.clipboard = true;
      await h.controller.checkClipboard();
      await h.controller.checkClipboard();
      expect(h.shown.length, 1);
      expect(h.shown.single.$1, [Uri.parse(_video)]);
      expect(h.shown.single.$2, LinkRecognitionSource.clipboard);
    },
  );

  test(
    'closing a confirmation does not repeatedly present the same clipboard',
    () async {
      h.clipboard = true;
      final dismissed = Completer<void>();
      h.onPresent = (_, _) => dismissed.future;
      final first = h.controller.checkClipboard();
      await _nextTurn();
      await h.controller.checkClipboard();
      expect(h.readCalls, 1);
      dismissed.complete();
      await first;
      await h.controller.checkClipboard();
      expect(h.shown.length, 1);
    },
  );

  test(
    'concurrent foreground checks share one in-flight clipboard read',
    () async {
      h.clipboard = true;
      final read = Completer<String?>();
      h.read = () => read.future;
      final first = h.controller.checkClipboard();
      await h.controller.checkClipboard();
      await h.controller.checkClipboard();
      expect(h.readCalls, 1);
      read.complete(_video);
      await first;
      expect(h.shown.length, 1);
    },
  );

  for (final condition in [
    'disabled',
    'background',
    'disposed',
    'invalidated',
  ]) {
    test('late clipboard result is ignored after $condition', () async {
      h.clipboard = true;
      final read = Completer<String?>();
      h.read = () => read.future;
      final pending = h.controller.checkClipboard();
      switch (condition) {
        case 'disabled':
          h.clipboard = false;
        case 'background':
          h.foreground = false;
        case 'disposed':
          h.controller.dispose();
        case 'invalidated':
          h.controller.invalidateClipboard();
      }
      read.complete(_video);
      await pending;
      expect(h.shown, isEmpty);
    });
  }

  test('toggle off and on invalidates an earlier clipboard read', () async {
    h.clipboard = true;
    final read = Completer<String?>();
    h.read = () => read.future;
    final pending = h.controller.checkClipboard();
    h.clipboard = false;
    h.controller.invalidateClipboard();
    h.clipboard = true;
    read.complete(_video);
    await pending;
    expect(h.shown, isEmpty);
    h.read = () async => _video;
    await h.controller.checkClipboard();
    expect(h.shown.length, 1);
  });

  test(
    'lifecycle invalidation preserves dismissal of unchanged clipboard text',
    () async {
      h.clipboard = true;
      await h.controller.checkClipboard();
      h.foreground = false;
      h.controller.invalidateClipboard();
      h.foreground = true;
      h.controller.invalidateClipboard();
      await h.controller.checkClipboard();
      expect(h.shown.length, 1);
    },
  );

  test(
    'explicit setting change can forget the earlier clipboard dismissal',
    () async {
      h.clipboard = true;
      await h.controller.checkClipboard();
      h.clipboard = false;
      h.controller.invalidateClipboard(forget: true);
      await h.controller.checkClipboard();
      expect(h.readCalls, 1);
      h.clipboard = true;
      await h.controller.checkClipboard();
      expect(h.shown.length, 2);
    },
  );

  test('quick resume during an old read rechecks fresh content once', () async {
    h.clipboard = true;
    final oldRead = Completer<String?>();
    h.read = () => h.readCalls == 1
        ? oldRead.future
        : Future.value('https://b23.tv/current');
    final pending = h.controller.checkClipboard();
    h.foreground = false;
    h.controller.invalidateClipboard();
    h.foreground = true;
    h.controller.invalidateClipboard();
    await h.controller.checkClipboard();
    await h.controller.checkClipboard();
    oldRead.complete(_video);
    await pending;
    expect(h.readCalls, 2);
    expect(h.shown.length, 1);
    expect(h.shown.single.$1, [Uri.parse('https://b23.tv/current')]);
  });

  test(
    'failed clipboard read releases the guard and allows a later retry',
    () async {
      h
        ..clipboard = true
        ..read = () async => throw StateError('simulated clipboard failure');
      await expectLater(h.controller.checkClipboard(), throwsStateError);
      h.read = () async => _video;
      await h.controller.checkClipboard();
      expect(h.readCalls, 2);
      expect(h.shown.length, 1);
    },
  );

  test(
    'unrelated clipboard text is ignored without presenting a dialog',
    () async {
      h
        ..clipboard = true
        ..read = () async => 'ordinary private text';
      await h.controller.checkClipboard();
      expect(h.shown, isEmpty);
    },
  );

  test(
    'disabled sharing rejects input without consulting the clipboard',
    () async {
      h.shares = false;
      await h.controller.receiveShare('id-1', _video);
      await h.controller.drain();
      expect(h.shown, isEmpty);
      expect(h.readCalls, 0);
    },
  );

  test('one share delivery ID is consumed only once', () async {
    await h.controller.receiveShare('id-1', _video);
    await h.controller.receiveShare('id-1', _video);
    expect(h.shown.length, 1);
    expect(h.shown.single.$2, LinkRecognitionSource.share);
    expect(h.readCalls, 0);
  });

  test(
    'background shares wait until foreground and retain their order',
    () async {
      h.foreground = false;
      await h.controller.receiveShare('id-1', _video);
      await h.controller.receiveShare('id-2', 'https://b23.tv/second');
      expect(h.shown, isEmpty);
      h.foreground = true;
      await h.controller.drain();
      expect(h.shown.map((event) => event.$1.single.toString()), [
        _video,
        'https://b23.tv/second',
      ]);
    },
  );

  test('turning sharing off discards queued background input', () async {
    h.foreground = false;
    await h.controller.receiveShare('id-1', _video);
    h
      ..shares = false
      ..foreground = true;
    await h.controller.drain();
    expect(h.shown, isEmpty);
  });

  test('multiple shares never present overlapping confirmations', () async {
    final gates = List.generate(3, (_) => Completer<void>());
    int active = 0;
    int maxActive = 0;
    int index = 0;
    h.onPresent = (_, _) async {
      active++;
      if (active > maxActive) maxActive = active;
      await gates[index++].future;
      active--;
    };
    final first = h.controller.receiveShare('id-1', _video);
    await _nextTurn();
    await h.controller.receiveShare('id-2', 'https://b23.tv/second');
    await h.controller.receiveShare('id-3', 'https://b23.tv/third');
    expect(h.shown.length, 1);
    for (final gate in gates) {
      gate.complete();
      await _nextTurn();
    }
    await first;
    expect(h.shown.length, 3);
    expect(maxActive, 1);
  });

  test(
    'explicit share supersedes an in-flight automatic clipboard result',
    () async {
      h.clipboard = true;
      final read = Completer<String?>();
      h.read = () => read.future;
      final pending = h.controller.checkClipboard();
      await h.controller.receiveShare('id-1', 'https://b23.tv/shared');
      read.complete(_video);
      await pending;
      expect(h.shown.length, 1);
      expect(h.shown.single.$2, LinkRecognitionSource.share);
    },
  );

  test(
    'share arriving during clipboard confirmation waits for dismissal',
    () async {
      h.clipboard = true;
      final dismissal = Completer<void>();
      h.onPresent = (_, source) async {
        if (source == LinkRecognitionSource.clipboard) await dismissal.future;
      };
      final clipboard = h.controller.checkClipboard();
      await _nextTurn();
      await h.controller.receiveShare('id-1', 'https://b23.tv/shared');
      expect(h.shown.length, 1);
      dismissal.complete();
      await clipboard;
      expect(h.shown.length, 2);
      expect(h.shown.last.$2, LinkRecognitionSource.share);
    },
  );

  test('disposing clears queued shares and rejects further input', () async {
    h.foreground = false;
    await h.controller.receiveShare('id-1', _video);
    h.controller.dispose();
    h
      ..foreground = true
      ..clipboard = true;
    await h.controller.drain();
    await h.controller.checkClipboard();
    await h.controller.receiveShare('id-2', _video);
    expect(h.shown, isEmpty);
    expect(h.readCalls, 0);
  });
}
