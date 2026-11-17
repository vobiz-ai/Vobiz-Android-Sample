import 'package:flutter/material.dart';

/// Renders the Vobiz brand mark at any size, keeping the original aspect ratio
/// (42 × 30 in the source SVG).
class VobizLogo extends StatelessWidget {
  const VobizLogo({super.key, this.width = 42});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 30 / 42,
      child: CustomPaint(painter: _VobizLogoPainter()),
    );
  }
}

class _VobizLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double sx = size.width / 42;
    final double sy = size.height / 30;

    final Paint p1 = Paint()..color = const Color(0xFFE83C00);
    final Path path1 = Path()
      ..moveTo(42 * sx, 14.7458 * sy)
      ..lineTo(42 * sx, 0)
      ..cubicTo(
          24.5641 * sx, 0, 12 * sx, 13.7288 * sy, 12 * sx, 30 * sy)
      ..lineTo(27.1282 * sx, 30 * sy)
      ..cubicTo(27.1282 * sx, 21.3559 * sy, 33.5385 * sx, 14.7458 * sy,
          42 * sx, 14.7458 * sy)
      ..close();
    canvas.drawPath(path1, p1);

    final Paint p2 = Paint()..color = const Color(0xFFE86A00);
    final Path path2 = Path()
      ..moveTo(0, 15 * sy)
      ..lineTo(0, 0)
      ..cubicTo(9.28572 * sx, 0, 15 * sx, 6.42857 * sy, 15 * sx, 15 * sy)
      ..lineTo(0, 15 * sy)
      ..close();
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
