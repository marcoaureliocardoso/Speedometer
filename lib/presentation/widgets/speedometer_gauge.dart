import 'dart:math' as math;

import 'package:flutter/material.dart';

class SpeedometerGauge extends StatelessWidget {
  const SpeedometerGauge({
    required this.speed,
    required this.roadSpeedLimit,
    super.key,
  });

  final double? speed;
  final double? roadSpeedLimit;

  @override
  Widget build(BuildContext context) {
    final limit = roadSpeedLimit;
    if (limit == null) {
      return Semantics(
        label: 'Limite indisponível. Escala do medidor indisponível.',
        child: ExcludeSemantics(
          child: Container(
            height: 208,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.speed_outlined, size: 36),
                SizedBox(height: 8),
                Text('Escala disponível após a confirmação do limite'),
              ],
            ),
          ),
        ),
      );
    }

    final gaugeMin = limit / 2;
    final isOverLimit = (speed ?? 0) > limit;
    final isBelowScale = (speed ?? 0) < gaugeMin;
    final semanticState = isOverLimit
        ? 'Acima do limite.'
        : isBelowScale
            ? 'Abaixo da faixa do medidor.'
            : 'Dentro da faixa do medidor.';

    return Semantics(
      label:
          'Velocidade ${(speed ?? 0).round()} quilômetros por hora. Limite ${limit.round()} quilômetros por hora. $semanticState',
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 1.45,
          child: CustomPaint(
            painter: _GaugePainter(
              speed: speed ?? 0,
              gaugeMin: gaugeMin,
              gaugeMax: limit,
              trackColor: Theme.of(context).colorScheme.outlineVariant,
              activeColor: isOverLimit
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              labelColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.speed,
    required this.gaugeMin,
    required this.gaugeMax,
    required this.trackColor,
    required this.activeColor,
    required this.labelColor,
  });

  final double speed;
  final double gaugeMin;
  final double gaugeMax;
  final Color trackColor;
  final Color activeColor;
  final Color labelColor;

  static const _startAngle = 135 * math.pi / 180;
  static const _sweepAngle = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .68);
    final radius = math.min(size.width * .39, size.height * .56);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweepAngle, false, trackPaint);

    final progress =
        ((speed - gaugeMin) / (gaugeMax - gaugeMin)).clamp(0.0, 1.0);
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    if (progress > 0) {
      canvas.drawArc(
          rect, _startAngle, _sweepAngle * progress, false, activePaint);
    }

    final tickStep = gaugeMax - gaugeMin <= 40
        ? 5.0
        : gaugeMax - gaugeMin <= 80
            ? 10.0
            : 20.0;
    final firstTick = (gaugeMin / tickStep).ceil() * tickStep;
    for (var value = firstTick; value < gaugeMax; value += tickStep) {
      _drawTick(
          canvas, center, radius, (value - gaugeMin) / (gaugeMax - gaugeMin));
    }

    _drawLabel(
        canvas, center, radius, _startAngle, gaugeMin.round().toString());
    _drawLabel(
      canvas,
      center,
      radius,
      _startAngle + _sweepAngle,
      gaugeMax.round().toString(),
    );
  }

  void _drawTick(Canvas canvas, Offset center, double radius, double progress) {
    final angle = _startAngle + (_sweepAngle * progress);
    final outer =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + 12);
    final inner =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + 4);
    canvas.drawLine(
      inner,
      outer,
      Paint()
        ..color = labelColor.withValues(alpha: .7)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    String label,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: labelColor,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final position =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + 31);
    painter.paint(
        canvas, position - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) {
    return speed != oldDelegate.speed ||
        gaugeMin != oldDelegate.gaugeMin ||
        gaugeMax != oldDelegate.gaugeMax ||
        trackColor != oldDelegate.trackColor ||
        activeColor != oldDelegate.activeColor ||
        labelColor != oldDelegate.labelColor;
  }
}
