import 'package:flutter/widgets.dart';

class ScanIcon extends StatelessWidget {
  const ScanIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size!;
    final color = theme.color!;
    return CustomPaint(
      size: Size.square(
        theme.applyTextScaling == true
            ? MediaQuery.textScalerOf(context).scale(size)
            : size,
      ),
      painter: _ScanIconPainter(
        color.withValues(alpha: color.a * (theme.opacity ?? 1)),
      ),
    );
  }
}

class _ScanIconPainter extends CustomPainter {
  const _ScanIconPainter(this.color);
  final Color color;

  static final _frame = Path()
    ..moveTo(3.5, 8)
    ..lineTo(3.5, 6)
    ..quadraticBezierTo(3.5, 3.5, 6, 3.5)
    ..lineTo(8, 3.5)
    ..moveTo(16, 3.5)
    ..lineTo(18, 3.5)
    ..quadraticBezierTo(20.5, 3.5, 20.5, 6)
    ..lineTo(20.5, 8)
    ..moveTo(20.5, 16)
    ..lineTo(20.5, 18)
    ..quadraticBezierTo(20.5, 20.5, 18, 20.5)
    ..lineTo(16, 20.5)
    ..moveTo(8, 20.5)
    ..lineTo(6, 20.5)
    ..quadraticBezierTo(3.5, 20.5, 3.5, 18)
    ..lineTo(3.5, 16)
    ..moveTo(4, 12)
    ..lineTo(20, 12);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(_frame, stroke)
      ..restore();
  }

  @override
  bool shouldRepaint(_ScanIconPainter oldDelegate) =>
      color != oldDelegate.color;
}
