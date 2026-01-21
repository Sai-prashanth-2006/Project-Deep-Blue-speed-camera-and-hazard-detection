import 'dart:math';
import 'package:flutter/material.dart';

class SpeedometerGadget extends StatelessWidget {
  final double currentSpeed;
  final int? speedLimit;
  final double size;

  const SpeedometerGadget({
    super.key,
    required this.currentSpeed,
    this.speedLimit,
    this.size = 120, // Slightly larger for premium feel
  });

  @override
  Widget build(BuildContext context) {
    // Determine color based on limit
    Color speedColor = Colors.cyan;
    if (speedLimit != null) {
      if (currentSpeed > speedLimit! + 5) {
        speedColor = Colors.redAccent;
      } else if (currentSpeed > speedLimit!) {
        speedColor = Colors.orangeAccent;
      } else {
        speedColor = Colors.greenAccent;
      }
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Arc Painter
          CustomPaint(
            size: Size(size, size),
            painter: _SpeedometerPainter(
              maxSpeed: 120, 
              currentSpeed: currentSpeed,
              speedLimit: speedLimit,
              speedColor: speedColor,
            ),
          ),
          // Digital Readout in Center
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentSpeed.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  height: 1.0,
                ),
              ),
              Text(
                "KM/H",
                style: TextStyle(
                  fontSize: size * 0.1,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          // Speed Limit Bug (Small Circle)
          if (speedLimit != null)
             Positioned(
               bottom: 10,
               child: Container(
                 padding: const EdgeInsets.all(4),
                 decoration: BoxDecoration(
                   color: Colors.white,
                   shape: BoxShape.circle,
                   border: Border.all(color: Colors.red, width: 2),
                   boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
                 ),
                 child: Text(
                   "$speedLimit",
                   style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                 ),
               ),
             ),
        ],
      ),
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double maxSpeed;
  final double currentSpeed;
  final int? speedLimit;
  final Color speedColor;

  _SpeedometerPainter({
    required this.maxSpeed,
    required this.currentSpeed,
    required this.speedLimit,
    required this.speedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = 10.0;

    // Background track (Grey)
    final bgPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Start angle: 135 degrees (bottom left) -> End angle: 45 degrees (bottom right)
    // Span: 270 degrees
    const startAngle = 135 * (pi / 180);
    const sweepAngle = 270 * (pi / 180);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Active speed arc
    final activePaint = Paint()
      ..color = speedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progress = (currentSpeed / maxSpeed).clamp(0.0, 1.0);
    final activeSweep = sweepAngle * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      startAngle,
      activeSweep,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter oldDelegate) {
    return oldDelegate.currentSpeed != currentSpeed || oldDelegate.speedColor != speedColor;
  }
}
