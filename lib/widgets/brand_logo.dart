import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;
  final bool showTagline;

  const BrandLogo({
    super.key,
    this.size = 240,
    this.showWordmark = false,
    this.showTagline = false,
  });

  @override
  Widget build(BuildContext context) {
    final wordmarkStyle = TextStyle(
      fontSize: size * 0.18,
      fontWeight: FontWeight.w800,
      height: 1,
      letterSpacing: -1.2,
      color: const Color(0xFF1A2C4D),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: const CustomPaint(painter: _BrandLogoPainter()),
        ),
        if (showWordmark) ...[
          SizedBox(height: size * 0.07),
          Text('Livrini', style: wordmarkStyle, textAlign: TextAlign.center),
        ],
        if (showTagline) ...[
          SizedBox(height: size * 0.03),
          Text(
            'Gestion intelligente des commandes COD',
            style: TextStyle(
              fontSize: size * 0.06,
              color: const Color(0xFF42536A),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _BrandLogoPainter extends CustomPainter {
  const _BrandLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final greenTeal = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF8ACF3D), Color(0xFF14B7B0)],
    );
    final navy = Paint()..color = const Color(0xFF1B2B49);
    final white = Paint()..color = Colors.white;

    Paint gradientPaint(Rect rect) {
      return Paint()
        ..shader = greenTeal.createShader(rect)
        ..isAntiAlias = true;
    }

    final leftBar = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.34,
        size.height * 0.12,
        size.width * 0.16,
        size.height * 0.56,
      ),
      Radius.circular(size.width * 0.08),
    );
    canvas.drawRRect(leftBar, gradientPaint(leftBar.outerRect));

    final baseBar = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.28,
        size.height * 0.72,
        size.width * 0.56,
        size.height * 0.15,
      ),
      Radius.circular(size.width * 0.075),
    );
    canvas.drawRRect(baseBar, gradientPaint(baseBar.outerRect));

    final bar1 = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.06,
        size.height * 0.47,
        size.width * 0.33,
        size.height * 0.06,
      ),
      Radius.circular(size.width * 0.03),
    );
    final bar2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.06,
        size.height * 0.58,
        size.width * 0.31,
        size.height * 0.06,
      ),
      Radius.circular(size.width * 0.03),
    );
    final bar3 = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.10,
        size.height * 0.69,
        size.width * 0.27,
        size.height * 0.06,
      ),
      Radius.circular(size.width * 0.03),
    );
    canvas.drawRRect(bar1, gradientPaint(bar1.outerRect));
    canvas.drawRRect(bar2, gradientPaint(bar2.outerRect));
    canvas.drawRRect(bar3, gradientPaint(bar3.outerRect));

    final boxBody = Path()
      ..moveTo(size.width * 0.46, size.height * 0.42)
      ..lineTo(size.width * 0.66, size.height * 0.35)
      ..lineTo(size.width * 0.86, size.height * 0.41)
      ..lineTo(size.width * 0.68, size.height * 0.49)
      ..close();
    canvas.drawPath(boxBody, navy);

    final boxFront = Path()
      ..moveTo(size.width * 0.55, size.height * 0.45)
      ..lineTo(size.width * 0.74, size.height * 0.53)
      ..lineTo(size.width * 0.74, size.height * 0.74)
      ..lineTo(size.width * 0.57, size.height * 0.67)
      ..close();
    canvas.drawPath(boxFront, navy);

    final boxSide = Path()
      ..moveTo(size.width * 0.74, size.height * 0.53)
      ..lineTo(size.width * 0.86, size.height * 0.49)
      ..lineTo(size.width * 0.86, size.height * 0.70)
      ..lineTo(size.width * 0.74, size.height * 0.74)
      ..close();
    canvas.drawPath(boxSide, navy);

    final ribbon = Path()
      ..moveTo(size.width * 0.56, size.height * 0.45)
      ..lineTo(size.width * 0.61, size.height * 0.47)
      ..lineTo(size.width * 0.61, size.height * 0.58)
      ..lineTo(size.width * 0.56, size.height * 0.55)
      ..close();
    canvas.drawPath(ribbon, white);

    final frontEdge = Path()
      ..moveTo(size.width * 0.66, size.height * 0.35)
      ..lineTo(size.width * 0.66, size.height * 0.49)
      ..moveTo(size.width * 0.66, size.height * 0.49)
      ..lineTo(size.width * 0.56, size.height * 0.45);
    canvas.drawPath(
      frontEdge,
      white
        ..strokeWidth = size.width * 0.02
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    final badgeCenter = Offset(size.width * 0.88, size.height * 0.28);
    canvas.drawCircle(
      badgeCenter,
      size.width * 0.08,
      Paint()
        ..shader = greenTeal.createShader(
          Rect.fromCircle(center: badgeCenter, radius: size.width * 0.08),
        ),
    );

    final checkPath = Path()
      ..moveTo(size.width * 0.84, size.height * 0.28)
      ..lineTo(size.width * 0.87, size.height * 0.31)
      ..lineTo(size.width * 0.92, size.height * 0.24);
    canvas.drawPath(
      checkPath,
      white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
