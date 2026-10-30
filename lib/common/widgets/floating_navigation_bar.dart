// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A compact navigation capsule. Dragging previews a destination; only a quiet
/// dwell commits it. Releasing a moving pointer never selects a destination.
class FloatingNavigationBar extends StatefulWidget {
  const FloatingNavigationBar({
    super.key,
    this.animationDuration = const Duration(milliseconds: 220),
    this.dragDwellDuration = const Duration(milliseconds: 200),
    this.selectedIndex = 0,
    required this.destinations,
    this.onDestinationSelected,
    this.interactionEnabled = true,
    this.backgroundColor,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.indicatorColor,
    this.indicatorShape,
    this.labelBehavior,
    this.overlayColor,
    this.labelTextStyle,
    this.labelPadding,
    this.bottomPadding = 12,
  }) : assert(destinations.length >= 2),
       assert(selectedIndex >= 0 && selectedIndex < destinations.length);

  final Duration animationDuration;
  final Duration dragDwellDuration;
  final int selectedIndex;
  final List<FloatingNavigationDestination> destinations;
  final ValueChanged<int>? onDestinationSelected;
  final bool interactionEnabled;
  final Color? backgroundColor;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final Color? indicatorColor;
  final ShapeBorder? indicatorShape;
  final NavigationDestinationLabelBehavior? labelBehavior;
  final WidgetStateProperty<Color?>? overlayColor;
  final WidgetStateProperty<TextStyle?>? labelTextStyle;
  final EdgeInsetsGeometry? labelPadding;
  final double bottomPadding;

  @override
  State<FloatingNavigationBar> createState() => _FloatingNavigationBarState();
}

class _FloatingNavigationBarState extends State<FloatingNavigationBar>
    with WidgetsBindingObserver {
  static const _trackPadding = 4.0;
  static const _motionTolerance = 4.0;
  GlobalKey _surfaceKey = GlobalKey();
  final _pointers = <int>{};
  final _allPointers = <int>{};
  final _focused = <int>{};
  final _hovered = <int>{};
  Timer? _dwell;
  bool _dragging = false;
  bool _suppressTap = false;
  Offset? _previewPosition;
  Offset? _previousPosition;
  double _motion = 0;
  int? _candidate;
  int? _submittedCandidate;
  int? _expectedSelection;

  bool get _enabled =>
      widget.interactionEnabled && widget.onDestinationSelected != null;

  @override
  void initState() {
    super.initState();
    assert(!widget.dragDwellDuration.isNegative);
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_trackPointers);
  }

  @override
  void didUpdateWidget(covariant FloatingNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedDestinations =
        oldWidget.destinations.length != widget.destinations.length ||
        List.generate(widget.destinations.length, (i) => i).any((i) {
          final before = oldWidget.destinations[i];
          final after = widget.destinations[i];
          return (before.key ?? before.label) != (after.key ?? after.label) ||
              before.enabled != after.enabled;
        });
    if (!_enabled ||
        changedDestinations ||
        oldWidget.dragDwellDuration != widget.dragDwellDuration) {
      _invalidateInteraction(rebuild: false);
    } else if (oldWidget.selectedIndex != widget.selectedIndex) {
      if (_dragging && _expectedSelection == widget.selectedIndex) {
        _expectedSelection = null;
      } else {
        _invalidateInteraction(rebuild: false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _invalidateInteraction(clearAllPointers: true);
    }
  }

  @override
  void didChangeViewFocus(ui.ViewFocusEvent event) {
    if (event.state == ui.ViewFocusState.unfocused) {
      _invalidateInteraction(clearAllPointers: true);
    }
  }

  @override
  void didChangeMetrics() => _resetDrag();

  @override
  void dispose() {
    _dwell?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_trackPointers);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // A platform can lose the final UP while focus is away. Retire that gesture
  // recognizer as well as its pointer IDs, so a fresh gesture can start safely.
  void _invalidateInteraction({
    bool rebuild = true,
    bool clearAllPointers = false,
  }) {
    final hadPointers = _pointers.isNotEmpty;
    final hadPreview = _previewPosition != null;
    _suppressTap = true;
    _pointers.clear();
    if (clearAllPointers) _allPointers.clear();
    if (hadPointers) _surfaceKey = GlobalKey();
    _resetDrag(rebuild: false);
    if (mounted && rebuild && (hadPointers || hadPreview)) setState(() {});
  }

  // Observe only ephemeral IDs, including a second finger outside the capsule.
  void _trackPointers(PointerEvent event) {
    if (event is PointerDownEvent) {
      _allPointers.add(event.pointer);
      if (_allPointers.length > 1 && _pointers.isNotEmpty) {
        _suppressTap = true;
        _resetDrag();
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _allPointers.remove(event.pointer);
    }
  }

  void _resetDrag({bool rebuild = true}) {
    _dwell?.cancel();
    _dwell = null;
    final hadPreview = _previewPosition != null;
    _dragging = false;
    _previewPosition = null;
    _previousPosition = null;
    _candidate = null;
    _submittedCandidate = null;
    _expectedSelection = null;
    _motion = 0;
    if (hadPreview && rebuild && mounted) setState(() {});
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) _suppressTap = false;
    _pointers.add(event.pointer);
    if (_pointers.length > 1) {
      _suppressTap = true;
      _resetDrag();
    }
  }

  void _pointerEnd(PointerEvent event) {
    if (_pointers.remove(event.pointer)) _resetDrag();
  }

  void _startDrag(DragStartDetails details) {
    if (!_enabled || _pointers.length != 1 || _suppressTap) return;
    _dragging = true;
    _suppressTap = true;
    _moveDrag(details.globalPosition);
  }

  void _moveDrag(Offset globalPosition) {
    if (!_dragging || !_enabled || _pointers.length != 1) return;
    final box = _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(globalPosition);
    final bounds = Offset.zero & box.size;
    if (!RRect.fromRectAndRadius(
      bounds,
      Radius.circular(box.size.height / 2),
    ).contains(local)) {
      _dwell?.cancel();
      _dwell = null;
      _candidate = null;
      _submittedCandidate = null;
      _previousPosition = null;
      _motion = 0;
      if (_previewPosition != null) setState(() => _previewPosition = null);
      return;
    }
    final slotWidth =
        (box.size.width - 2 * _trackPadding) / widget.destinations.length;
    var physical = ((local.dx - _trackPadding) / slotWidth).floor();
    physical = physical.clamp(0, widget.destinations.length - 1);
    final index = Directionality.of(context) == TextDirection.rtl
        ? widget.destinations.length - 1 - physical
        : physical;
    final candidate = widget.destinations[index].enabled ? index : null;
    final changed = candidate != _candidate;
    if (_previousPosition case final previous?) {
      _motion += (local - previous).distance;
    }
    _previousPosition = local;
    if (changed || _motion >= _motionTolerance || _previewPosition == null) {
      _motion = 0;
      if (changed) _submittedCandidate = null;
      _candidate = candidate;
      _armDwell();
    }
    setState(() => _previewPosition = local);
  }

  void _armDwell() {
    _dwell?.cancel();
    _dwell = null;
    final index = _candidate;
    if (index == null ||
        index == widget.selectedIndex ||
        index == _submittedCandidate) {
      return;
    }
    _dwell = Timer(widget.dragDwellDuration, () {
      _dwell = null;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!mounted ||
          !_dragging ||
          !_enabled ||
          _pointers.length != 1 ||
          _candidate != index ||
          _previewPosition == null ||
          index == widget.selectedIndex ||
          index == _submittedCandidate ||
          !widget.destinations[index].enabled ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      _submittedCandidate = index;
      _expectedSelection = index;
      widget.onDestinationSelected!(index);
    });
  }

  void _activate(int index) {
    if (!_enabled || !widget.destinations[index].enabled) return;
    _resetDrag();
    widget.onDestinationSelected!(index);
  }

  void _setHighlight(Set<int> values, int index, bool value) {
    if (!mounted) return;
    if (value ? values.add(index) : values.remove(index)) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final navTheme = NavigationBarTheme.of(context);
    final safe = MediaQuery.viewPaddingOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final height = math.max(64.0, scaler.scale(12) + 44);
    final labelBehavior =
        widget.labelBehavior ??
        navTheme.labelBehavior ??
        NavigationDestinationLabelBehavior.alwaysShow;
    final radius = BorderRadius.circular(height / 2);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final duration = reduceMotion ? Duration.zero : widget.animationDuration;
    final baseColor =
        widget.backgroundColor ??
        navTheme.backgroundColor ??
        colors.surfaceContainer;
    final surface = ElevationOverlay.applySurfaceTint(
      baseColor,
      widget.surfaceTintColor ?? navTheme.surfaceTintColor,
      widget.elevation ?? navTheme.elevation ?? 3,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final outerPadding = EdgeInsets.fromLTRB(
          safe.left + 16,
          0,
          safe.right + 16,
          safe.bottom + widget.bottomPadding,
        );
        final width = math.min(
          widget.destinations.length * 86.0 + 8,
          math.max(0.0, maxWidth - outerPadding.horizontal),
        );
        final slotWidth =
            (width - 2 * _trackPadding) / widget.destinations.length;
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final selectedPhysical = rtl
            ? widget.destinations.length - 1 - widget.selectedIndex
            : widget.selectedIndex;
        final firstCenter = _trackPadding + slotWidth / 2;
        final lastCenter = width - _trackPadding - slotWidth / 2;
        final center =
            _previewPosition?.dx.clamp(firstCenter, lastCenter) ??
            firstCenter + selectedPhysical * slotWidth;
        final preview = _previewPosition == null ? null : _candidate;

        return Padding(
          padding: outerPadding,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color:
                      widget.shadowColor ??
                      navTheme.shadowColor ??
                      colors.shadow.withValues(
                        alpha: theme.brightness == Brightness.dark ? .28 : .12,
                      ),
                  blurRadius: 22,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: SizedBox(
              key: const ValueKey('floating-nav-capsule'),
              width: width,
              height: height,
              child: Listener(
                onPointerDown: _pointerDown,
                onPointerUp: _pointerEnd,
                onPointerCancel: _pointerEnd,
                child: GestureDetector(
                  key: _surfaceKey,
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: _enabled ? _startDrag : null,
                  onPanUpdate: _enabled
                      ? (details) => _moveDrag(details.globalPosition)
                      : null,
                  onPanEnd: _enabled ? (_) => _resetDrag() : null,
                  onPanCancel: _enabled ? _resetDrag : null,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: BackdropFilter(
                      enabled: !highContrast,
                      filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: surface.withValues(
                            alpha: highContrast ? 1 : surface.a * .95,
                          ),
                          borderRadius: radius,
                          border: Border.all(
                            color: colors.outlineVariant.withValues(alpha: .45),
                          ),
                        ),
                        child: Stack(
                          children: [
                            AnimatedPositioned(
                              duration: _previewPosition == null
                                  ? duration
                                  : Duration.zero,
                              curve: Curves.easeOutCubic,
                              left: center - slotWidth / 2 + 2,
                              top: _trackPadding,
                              bottom: _trackPadding,
                              width: math.max(0, slotWidth - 4),
                              child: DecoratedBox(
                                key: const ValueKey('floating-nav-indicator'),
                                decoration: ShapeDecoration(
                                  color:
                                      widget.indicatorColor ??
                                      navTheme.indicatorColor ??
                                      colors.secondaryContainer,
                                  shape:
                                      widget.indicatorShape ??
                                      navTheme.indicatorShape ??
                                      const StadiumBorder(),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(_trackPadding),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (
                                    var i = 0;
                                    i < widget.destinations.length;
                                    i++
                                  )
                                    Expanded(
                                      child: _buildDestination(
                                        i,
                                        preview,
                                        labelBehavior,
                                        navTheme,
                                        colors,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDestination(
    int index,
    int? preview,
    NavigationDestinationLabelBehavior labelBehavior,
    NavigationBarThemeData theme,
    ColorScheme colors,
  ) {
    final destination = widget.destinations[index];
    final enabled = _enabled && destination.enabled;
    final selected = index == widget.selectedIndex;
    final highlighted = index == (preview ?? widget.selectedIndex);
    final showLabel =
        labelBehavior == NavigationDestinationLabelBehavior.alwaysShow ||
        labelBehavior == NavigationDestinationLabelBehavior.onlyShowSelected &&
            highlighted;
    final states = <WidgetState>{
      if (highlighted) WidgetState.selected,
      if (!enabled) WidgetState.disabled,
      if (_focused.contains(index)) WidgetState.focused,
      if (_hovered.contains(index)) WidgetState.hovered,
    };
    final color = !enabled
        ? colors.onSurface.withValues(alpha: .38)
        : highlighted
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    final iconTheme =
        theme.iconTheme?.resolve(states) ??
        IconThemeData(color: color, size: 24);
    final textStyle =
        widget.labelTextStyle?.resolve(states) ??
        theme.labelTextStyle?.resolve(states) ??
        TextStyle(
          fontSize: 12,
          fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
          color: color,
          height: 1.15,
        );
    final overlay =
        widget.overlayColor?.resolve(states) ??
        theme.overlayColor?.resolve(states) ??
        (_focused.contains(index)
            ? colors.primary.withValues(alpha: .12)
            : _hovered.contains(index)
            ? colors.onSurface.withValues(alpha: .06)
            : Colors.transparent);

    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => _setHighlight(_focused, index, value),
      onShowHoverHighlight: (value) => _setHighlight(_hovered, index, value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate(index);
            return null;
          },
        ),
      },
      child: Semantics(
        selected: selected,
        button: true,
        enabled: enabled,
        label: showLabel ? null : destination.label,
        onTap: enabled ? () => _activate(index) : null,
        child: Tooltip(
          message: destination.tooltip ?? destination.label,
          excludeFromSemantics: true,
          child: GestureDetector(
            key: ValueKey('floating-nav-destination-$index'),
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: enabled
                ? () {
                    if (!_suppressTap) _activate(index);
                  }
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: overlay,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconTheme.merge(
                    data: iconTheme,
                    child: highlighted
                        ? destination.selectedIcon ?? destination.icon
                        : destination.icon,
                  ),
                  if (showLabel)
                    Padding(
                      padding:
                          widget.labelPadding ??
                          theme.labelPadding ??
                          const EdgeInsets.only(top: 3),
                      child: Text(
                        destination.label,
                        style: textStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FloatingNavigationDestination extends StatelessWidget {
  const FloatingNavigationDestination({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.tooltip,
    this.enabled = true,
  });

  final Widget icon;
  final Widget? selectedIcon;
  final String label;
  final String? tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [icon, Text(label)],
  );
}
