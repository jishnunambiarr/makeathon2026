import 'dart:math' as math;

import 'package:campus_flutter/agentComponent/model/agent_state.dart';
import 'package:flutter/material.dart';

class OrbWidget extends StatefulWidget {
  final AgentState state;
  final Color color1;
  final Color color2;

  /// 0..1 input volume
  final double input;

  /// 0..1 output volume
  final double output;

  const OrbWidget({
    super.key,
    required this.state,
    this.color1 = const Color(0xFFCADCFC),
    this.color2 = const Color(0xFFA0B9D1),
    this.input = 0,
    this.output = 0.3,
  });

  @override
  State<OrbWidget> createState() => _OrbWidgetState();
}

class _OrbWidgetState extends State<OrbWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 20))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return CustomPaint(
            painter: _OrbPainter(
              t: _c.value * 2 * math.pi,
              state: widget.state,
              color1: widget.color1,
              color2: widget.color2,
              input: widget.input.clamp(0.0, 1.0),
              output: widget.output.clamp(0.0, 1.0),
              isDark: Theme.of(context).brightness == Brightness.dark,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t;
  final AgentState state;
  final Color color1;
  final Color color2;
  final double input;
  final double output;
  final bool isDark;

  _OrbPainter({
    required this.t,
    required this.state,
    required this.color1,
    required this.color2,
    required this.input,
    required this.output,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = math.min(size.width, size.height) * 0.35;

    canvas.save();
    canvas.translate(center.dx, center.dy);

    final basePulse = _pulse(t, state);
    final inPulse = 0.15 + 0.35 * input;
    final outPulse = 0.15 + 0.55 * output;

    final scale = 0.95 + 0.10 * basePulse + 0.08 * outPulse;

    // Soft background glow
    final glowPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = RadialGradient(
        colors: [
          color1.withOpacity(isDark ? 0.35 : 0.25),
          color2.withOpacity(isDark ? 0.18 : 0.12),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 2.2));
    canvas.drawCircle(Offset.zero, r * 2.0 * (0.9 + 0.2 * basePulse), glowPaint);

    canvas.scale(scale);

    // Main orb body with subtle swirl
    final body = Paint()
      ..shader = SweepGradient(
        colors: [
          _mix(color1, color2, 0.15),
          color1,
          _mix(color2, color1, 0.35),
          color2,
          _mix(color1, color2, 0.6),
        ],
        stops: const [0.0, 0.25, 0.48, 0.75, 1.0],
        transform: GradientRotation(t * 0.15),
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
    canvas.drawCircle(Offset.zero, r, body);

    // Inner highlight
    final highlight = Paint()
      ..blendMode = BlendMode.screen
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(isDark ? 0.16 : 0.22),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(
        Rect.fromCircle(center: Offset(-r * 0.2, -r * 0.25), radius: r * 1.2),
      );
    canvas.drawCircle(Offset(-r * 0.15, -r * 0.18), r * 0.95, highlight);

    // Ring reacts to input volume
    final ringR = r * (1.05 + 0.2 * inPulse);
    final ringWidth = r * 0.06 * (0.8 + 0.6 * inPulse);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..color = Colors.white.withOpacity(isDark ? 0.18 : 0.14)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, ringWidth * 0.75);
    canvas.drawCircle(Offset.zero, ringR, ringPaint);

    canvas.restore();
  }

  double _pulse(double t, AgentState s) {
    switch (s) {
      case AgentState.idle:
        return 0.35 + 0.10 * math.sin(t * 0.4);
      case AgentState.thinking:
        return 0.45 + 0.10 * math.sin(t * 0.7) * math.sin(t * 0.21 + 1.2);
      case AgentState.listening:
        return 0.55 + 0.25 * math.sin(t * 2.2);
      case AgentState.talking:
        return 0.70 + 0.20 * math.sin(t * 3.2);
    }
  }

  Color _mix(Color a, Color b, double t) {
    return Color.lerp(a, b, t.clamp(0.0, 1.0))!;
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.state != state ||
        oldDelegate.color1 != color1 ||
        oldDelegate.color2 != color2 ||
        oldDelegate.input != input ||
        oldDelegate.output != output ||
        oldDelegate.isDark != isDark;
  }
}

