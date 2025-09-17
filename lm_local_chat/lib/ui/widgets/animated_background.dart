import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AnimatedWaveBackground extends StatefulWidget {
  const AnimatedWaveBackground({
    super.key,
    required this.child,
    this.enableShader = true,
  });

  final Widget child;
  final bool enableShader;

  @override
  State<AnimatedWaveBackground> createState() => _AnimatedWaveBackgroundState();
}

class _AnimatedWaveBackgroundState extends State<AnimatedWaveBackground>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset(
      'assets/shaders/wave_bg.frag',
    );
    setState(() {
      _shader = program.fragmentShader();
    });
  }

  void _onTick(Duration elapsed) {
    setState(() {
      _time = elapsed.inMilliseconds / 1000.0;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final startColor = isDark
        ? const Color(0xFF0E0E0E)
        : const Color(0xFFF2F2F2);
    final endColor = isDark ? const Color(0xFF202020) : const Color(0xFFE0E0E0);
    if (!widget.enableShader) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [startColor, endColor],
          ),
        ),
        child: widget.child,
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _shader == null
          ? Container(color: startColor, child: widget.child)
          : _ShaderBackdrop(
              shader: _shader!,
              time: _time,
              startColor: startColor,
              endColor: endColor,
              child: widget.child,
            ),
    );
  }
}

class _ShaderBackdrop extends StatelessWidget {
  const _ShaderBackdrop({
    required this.shader,
    required this.time,
    required this.startColor,
    required this.endColor,
    required this.child,
  });

  final ui.FragmentShader shader;
  final double time;
  final Color startColor;
  final Color endColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          painter: _WavePainter(shader, time, startColor, endColor),
          child: child,
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.shader, this.time, this.startColor, this.endColor);

  final ui.FragmentShader shader;
  final double time;
  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, time)
      ..setFloat(1, size.width)
      ..setFloat(2, size.height)
      ..setFloat(3, startColor.r)
      ..setFloat(4, startColor.g)
      ..setFloat(5, startColor.b)
      ..setFloat(6, endColor.r)
      ..setFloat(7, endColor.g)
      ..setFloat(8, endColor.b);
    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.shader != shader ||
        oldDelegate.startColor != startColor ||
        oldDelegate.endColor != endColor;
  }
}
