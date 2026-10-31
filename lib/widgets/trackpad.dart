import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class Trackpad extends StatefulWidget {
  const Trackpad({super.key, required this.onMove, required this.onClick, required this.connected});
  final void Function(double dx, double dy) onMove;
  final void Function(String button) onClick;
  final bool connected;

  @override
  State<Trackpad> createState() => _TrackpadState();
}

class _TrackpadState extends State<Trackpad> {
  Offset? _last;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanStart: (d) => _last = d.localPosition,
    onPanUpdate: (d) {
      final prior = _last ?? d.localPosition;
      final delta = d.localPosition - prior;
      _last = d.localPosition;
      widget.onMove(delta.dx, delta.dy);
    },
    onPanEnd: (_) => _last = null,
    onTap: () => widget.onClick('left'),
    onLongPress: () => widget.onClick('right'),
    child: Container(
      height: 220,
      decoration: BoxDecoration(color: const Color(0xFFEAF2EC), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFDCE9DE))),
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _DotPainter())),
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.touch_app_rounded, size: 35, color: const Color(0xFF41845E).withOpacity(.75)),
          const SizedBox(height: 8),
          const Text('Move your finger to control the pointer', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF365B45))),
          const SizedBox(height: 5),
          const Text('Tap for left click  ·  Hold for right click', style: TextStyle(fontSize: 12, color: Color(0xFF708178))),
        ])),
      ]),
    ),
  );
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFBCD2C1)..strokeWidth = 1.2;
    for (double x = 18; x < size.width; x += 22) {
      for (double y = 18; y < size.height; y += 22) canvas.drawCircle(Offset(x,y), 1, paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
