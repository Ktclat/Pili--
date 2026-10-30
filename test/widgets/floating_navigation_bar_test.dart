import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/floating_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _destination(int index) =>
    find.byKey(ValueKey('floating-nav-destination-$index'));

const _labels = ['首页', '动态', '我的'];
const _icons = [
  Icons.home_outlined,
  Icons.forum_outlined,
  Icons.person_outline,
];

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    this.count = 3,
    this.disabledIndex = -1,
    this.autoSelect = true,
    this.textScale = 1,
    this.direction = TextDirection.ltr,
    this.brightness = Brightness.light,
    this.reducedMotion = false,
    this.safePadding = EdgeInsets.zero,
  });

  final int count;
  final int disabledIndex;
  final bool autoSelect;
  final double textScale;
  final TextDirection direction;
  final Brightness brightness;
  final bool reducedMotion;
  final EdgeInsets safePadding;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final calls = <int>[];
  int selectedIndex = 0;
  bool interactionEnabled = true;
  bool hasCallback = true;
  late List<int> order = List.generate(widget.count, (index) => index);

  void update({
    int? selected,
    bool? enabled,
    bool? callback,
    bool reverse = false,
  }) {
    setState(() {
      if (selected != null) selectedIndex = selected;
      if (enabled != null) interactionEnabled = enabled;
      if (callback != null) hasCallback = callback;
      if (reverse) order = order.reversed.toList();
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: widget.brightness,
      ),
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(widget.textScale),
            disableAnimations: widget.reducedMotion,
            viewPadding: widget.safePadding,
            padding: widget.safePadding,
          ),
          child: Directionality(
            textDirection: widget.direction,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FloatingNavigationBar(
                selectedIndex: selectedIndex,
                interactionEnabled: interactionEnabled,
                onDestinationSelected: hasCallback
                    ? (index) {
                        calls.add(index);
                        if (widget.autoSelect) {
                          setState(() => selectedIndex = index);
                        }
                      }
                    : null,
                destinations: [
                  for (final id in order)
                    FloatingNavigationDestination(
                      key: ValueKey('tab-$id'),
                      label: _labels[id],
                      icon: Icon(_icons[id]),
                      selectedIcon: Icon(_icons[id]),
                      enabled: id != widget.disabledIndex,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<_HarnessState> _mount(
  WidgetTester tester, {
  int count = 3,
  int disabledIndex = -1,
  bool autoSelect = true,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  Brightness brightness = Brightness.light,
  bool reducedMotion = false,
  EdgeInsets safePadding = EdgeInsets.zero,
}) async {
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    _Harness(
      key: key,
      count: count,
      disabledIndex: disabledIndex,
      autoSelect: autoSelect,
      textScale: textScale,
      direction: direction,
      brightness: brightness,
      reducedMotion: reducedMotion,
      safePadding: safePadding,
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

Future<TestGesture> _dragTo(WidgetTester tester, int index) async {
  final gesture = await tester.startGesture(tester.getCenter(_destination(0)));
  await gesture.moveTo(tester.getCenter(_destination(index)));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('tap selects immediately and keeps current-tab tap behavior', (
    tester,
  ) async {
    final state = await _mount(tester);
    await tester.tap(_destination(0));
    await tester.pump();
    await tester.tap(_destination(2));
    await tester.pump();
    expect(state.calls, [0, 2]);
    expect(state.selectedIndex, 2);
  });

  testWidgets('drag previews before the 200ms dwell and submits exactly once', (
    tester,
  ) async {
    final state = await _mount(tester);
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 199));
    expect(state.calls, isEmpty);
    expect(state.selectedIndex, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(state.calls, [1]);
    expect(state.selectedIndex, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(state.calls, [1]);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.calls, [1]);
  });

  testWidgets('a fast sweep and early release never commit the preview', (
    tester,
  ) async {
    final state = await _mount(tester);
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 70));
    await gesture.moveTo(tester.getCenter(_destination(2)));
    await tester.pump(const Duration(milliseconds: 70));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    expect(state.selectedIndex, 0);
  });

  testWidgets('cumulative small movements in one tab reset the quiet period', (
    tester,
  ) async {
    final state = await _mount(tester);
    final center = tester.getCenter(_destination(1)) - const Offset(16, 0);
    final gesture = await tester.startGesture(
      tester.getCenter(_destination(0)),
    );
    await gesture.moveTo(center);
    await tester.pump();
    for (var step = 1; step <= 6; step++) {
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.moveTo(center + Offset(2.0 * step, 0));
      await tester.pump();
      expect(state.calls, isEmpty, reason: 'Still moving inside the same tab');
    }
    await tester.pump(const Duration(milliseconds: 199));
    expect(state.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(state.calls, [1]);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the pill follows motion continuously within one destination', (
    tester,
  ) async {
    final state = await _mount(tester);
    final gesture = await _dragTo(tester, 1);
    final before = tester.getCenter(
      find.byKey(const ValueKey('floating-nav-indicator')),
    );
    await gesture.moveBy(const Offset(8, 0));
    await tester.pump();
    final after = tester.getCenter(
      find.byKey(const ValueKey('floating-nav-indicator')),
    );
    expect(after.dx - before.dx, closeTo(8, 1));
    expect(state.calls, isEmpty);
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('a committed dwell can continue dragging to another page', (
    tester,
  ) async {
    final state = await _mount(tester);
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.calls, [1]);
    await gesture.moveTo(tester.getCenter(_destination(2)));
    await tester.pump(const Duration(milliseconds: 199));
    expect(state.calls, [1]);
    await tester.pump(const Duration(milliseconds: 1));
    expect(state.calls, [1, 2]);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.calls, [1, 2]);
  });

  testWidgets('returning to the current page does not trigger a refresh', (
    tester,
  ) async {
    final state = await _mount(tester);
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(_destination(0)));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      '${cancel ? 'pointer cancellation' : 'leaving the capsule'} cancels pending dwell',
      (
        tester,
      ) async {
        final state = await _mount(tester);
        final gesture = await _dragTo(tester, 1);
        await tester.pump(const Duration(milliseconds: 100));
        if (cancel) {
          await gesture.cancel();
        } else {
          final capsule = tester.getRect(
            find.byKey(const ValueKey('floating-nav-capsule')),
          );
          await gesture.moveTo(capsule.topCenter - const Offset(0, 24));
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(state.calls, isEmpty);
        if (!cancel) await gesture.up();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('a second pointer cancels the whole drag interaction', (
    tester,
  ) async {
    final state = await _mount(tester);
    final first = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 100));
    final second = await tester.startGesture(
      tester.getCenter(_destination(2)),
      pointer: 2,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.calls, isEmpty);
    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
  });

  testWidgets('a second pointer outside the capsule also cancels dwell', (
    tester,
  ) async {
    final state = await _mount(tester);
    final first = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 100));
    final second = await tester.startGesture(const Offset(16, 16), pointer: 2);
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.calls, isEmpty);
    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
  });

  for (final change in ['selected page', 'hidden bar', 'callback', 'order']) {
    testWidgets('changing $change invalidates pending dwell', (tester) async {
      final state = await _mount(tester);
      final gesture = await _dragTo(tester, 1);
      await tester.pump(const Duration(milliseconds: 100));
      switch (change) {
        case 'selected page':
          state.update(selected: 2);
        case 'hidden bar':
          state.update(enabled: false);
        case 'callback':
          state.update(callback: false);
        case 'order':
          state.update(reverse: true);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.calls, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(state.calls, isEmpty);
    });
  }

  testWidgets('backgrounding invalidates pending dwell', (tester) async {
    final state = await _mount(tester);
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.calls, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
  });

  testWidgets('disposing with pending dwell has no late callback', (
    tester,
  ) async {
    final state = await _mount(tester);
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    expect(state.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('losing window focus cancels pending dwell', (tester) async {
    final state = await _mount(tester);
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleViewFocusChanged(
      ui.ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ui.ViewFocusState.unfocused,
        direction: ui.ViewFocusDirection.undefined,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.calls, isEmpty);
    tester.binding.handleViewFocusChanged(
      ui.ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ui.ViewFocusState.focused,
        direction: ui.ViewFocusDirection.undefined,
      ),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
  });

  testWidgets('a covered route cannot commit a pending page change', (
    tester,
  ) async {
    final state = await _mount(tester);
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 100));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator))
      ..push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('another route')),
        ),
      );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.calls, isEmpty);
    await gesture.up();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
  });

  testWidgets('a lost pointer-up in the background does not block a new drag', (
    tester,
  ) async {
    final state = await _mount(tester);
    final staleGesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    // The OS need not deliver the old pointer-up after losing window focus.
    final freshGesture = await tester.startGesture(
      tester.getCenter(_destination(0)),
      pointer: 17,
    );
    await freshGesture.moveTo(tester.getCenter(_destination(2)));
    // A delayed cancellation from the old stream must not cancel the new one.
    await staleGesture.cancel();
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.calls, [2]);
    await freshGesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('disabled destinations and absent callbacks cannot navigate', (
    tester,
  ) async {
    final state = await _mount(tester, disabledIndex: 1);
    await tester.tap(_destination(1));
    await tester.pump();
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
    state.update(callback: false);
    await tester.pump();
    await tester.tap(_destination(2));
    await tester.pumpAndSettle();
    expect(state.calls, isEmpty);
  });

  testWidgets('semantics expose actual selected page while previewing', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _mount(tester);
      final gesture = await _dragTo(tester, 1);
      expect(
        tester.getSemantics(_destination(0)).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        tester.getSemantics(_destination(1)).flagsCollection.isSelected,
        ui.Tristate.isFalse,
      );
      expect(
        tester.getSemantics(_destination(1)).flagsCollection.isButton,
        isTrue,
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('keyboard focus can activate destinations', (tester) async {
    final state = await _mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(state.calls, [0]);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(state.calls, [0, 1]);
  });

  testWidgets('RTL maps leftward dragging to the next logical destination', (
    tester,
  ) async {
    final state = await _mount(tester, direction: TextDirection.rtl);
    expect(
      tester.getCenter(_destination(0)).dx,
      greaterThan(tester.getCenter(_destination(1)).dx),
    );
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.calls, [1]);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '320dp, 2x text, safe insets and $brightness fit without overflow',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = await _mount(
          tester,
          textScale: 2,
          brightness: brightness,
          safePadding: const EdgeInsets.fromLTRB(12, 0, 16, 28),
        );
        final capsule = tester.getRect(
          find.byKey(const ValueKey('floating-nav-capsule')),
        );
        expect(capsule.left, greaterThanOrEqualTo(12));
        expect(capsule.right, lessThanOrEqualTo(304));
        expect(capsule.bottom, lessThanOrEqualTo(732));
        expect(tester.takeException(), isNull);
        await tester.tap(_destination(2));
        await tester.pumpAndSettle();
        expect(state.calls, [2]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('two destinations and reduced motion preserve dwell behavior', (
    tester,
  ) async {
    final state = await _mount(tester, count: 2, reducedMotion: true);
    final gesture = await _dragTo(tester, 1);
    await tester.pump(const Duration(milliseconds: 199));
    expect(state.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(state.calls, [1]);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
