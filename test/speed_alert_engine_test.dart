import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/domain/entities/voice_alert.dart';
import 'package:speedometer/domain/services/speed_alert_engine.dart';

void main() {
  test('confirma alerta acima do limite em duas leituras', () {
    final engine = SpeedAlertEngine();

    expect(engine.process(speedKmh: 40, isValid: true, roadSpeedLimit: 40),
        isNull);
    expect(engine.process(speedKmh: 41, isValid: true, roadSpeedLimit: 40),
        isNull);

    final alert =
        engine.process(speedKmh: 42, isValid: true, roadSpeedLimit: 40);
    expect(alert?.kind, VoiceAlertKind.aboveLimit);
  });

  test('confirma alerta abaixo da metade e não dispara no limiar', () {
    final engine = SpeedAlertEngine();

    engine.process(speedKmh: 20, isValid: true, roadSpeedLimit: 40);
    expect(engine.process(speedKmh: 20, isValid: true, roadSpeedLimit: 40),
        isNull);
    expect(engine.process(speedKmh: 19, isValid: true, roadSpeedLimit: 40),
        isNull);

    final alert =
        engine.process(speedKmh: 18, isValid: true, roadSpeedLimit: 40);
    expect(alert?.kind, VoiceAlertKind.belowHalfLimit);
  });

  test('não confirma alerta com leitura inválida', () {
    final engine = SpeedAlertEngine();

    engine.process(speedKmh: 40, isValid: true, roadSpeedLimit: 40);
    engine.process(speedKmh: 41, isValid: true, roadSpeedLimit: 40);
    expect(engine.process(speedKmh: 42, isValid: false, roadSpeedLimit: 40),
        isNull);
  });
}
