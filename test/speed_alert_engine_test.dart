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

  test('anuncia limite personalizado após duas leituras acima do valor', () {
    final engine = SpeedAlertEngine();

    engine.process(
        speedKmh: 80,
        isValid: true,
        roadSpeedLimit: null,
        customSpeedLimitKmh: 80);
    expect(
      engine.process(
          speedKmh: 81,
          isValid: true,
          roadSpeedLimit: null,
          customSpeedLimitKmh: 80),
      isNull,
    );

    final alert = engine.process(
        speedKmh: 82,
        isValid: true,
        roadSpeedLimit: null,
        customSpeedLimitKmh: 80);
    expect(alert?.kind, VoiceAlertKind.customSpeedLimitExceeded);
    expect(alert?.message, 'Limite de velocidade 80Km/h ultrapassado.');
  });

  test('rearma o limite personalizado somente após duas leituras seguras', () {
    final engine = SpeedAlertEngine();

    for (final speed in [80.0, 81.0]) {
      engine.process(
          speedKmh: speed,
          isValid: true,
          roadSpeedLimit: null,
          customSpeedLimitKmh: 80);
    }
    expect(
      engine
          .process(
              speedKmh: 82,
              isValid: true,
              roadSpeedLimit: null,
              customSpeedLimitKmh: 80)
          ?.kind,
      VoiceAlertKind.customSpeedLimitExceeded,
    );

    expect(
      engine.process(
          speedKmh: 83,
          isValid: true,
          roadSpeedLimit: null,
          customSpeedLimitKmh: 80),
      isNull,
    );
    engine.process(
        speedKmh: 78,
        isValid: true,
        roadSpeedLimit: null,
        customSpeedLimitKmh: 80);
    engine.process(
        speedKmh: 78,
        isValid: true,
        roadSpeedLimit: null,
        customSpeedLimitKmh: 80);
    engine.process(
        speedKmh: 81,
        isValid: true,
        roadSpeedLimit: null,
        customSpeedLimitKmh: 80);

    expect(
      engine
          .process(
              speedKmh: 82,
              isValid: true,
              roadSpeedLimit: null,
              customSpeedLimitKmh: 80)
          ?.kind,
      VoiceAlertKind.customSpeedLimitExceeded,
    );
  });

  test('reinicia o alerta personalizado ao iniciar uma nova sessão', () {
    final engine = SpeedAlertEngine();

    for (final speed in [80.0, 81.0, 82.0]) {
      engine.process(
          speedKmh: speed,
          isValid: true,
          roadSpeedLimit: null,
          customSpeedLimitKmh: 80);
    }
    engine.reset();
    engine.process(
        speedKmh: 80,
        isValid: true,
        roadSpeedLimit: null,
        customSpeedLimitKmh: 80);
    engine.process(
        speedKmh: 81,
        isValid: true,
        roadSpeedLimit: null,
        customSpeedLimitKmh: 80);

    expect(
      engine
          .process(
              speedKmh: 82,
              isValid: true,
              roadSpeedLimit: null,
              customSpeedLimitKmh: 80)
          ?.kind,
      VoiceAlertKind.customSpeedLimitExceeded,
    );
  });

  test('confirma faixa de 5 km/h em aceleração', () {
    final engine = SpeedAlertEngine();
    engine.process(speedKmh: 14.9, isValid: true, roadSpeedLimit: null);
    expect(engine.process(speedKmh: 15.1, isValid: true, roadSpeedLimit: null),
        isNull);
    expect(
        engine
            .process(speedKmh: 15.2, isValid: true, roadSpeedLimit: null)
            ?.message,
        '15 quilômetros por hora.');
  });

  test('confirma faixa de 10 km/h quando configurada', () {
    final engine = SpeedAlertEngine();
    engine.process(
        speedKmh: 14.9,
        isValid: true,
        roadSpeedLimit: null,
        bandIntervalKmh: 10);
    expect(
        engine.process(
            speedKmh: 15.1,
            isValid: true,
            roadSpeedLimit: null,
            bandIntervalKmh: 10),
        isNull);
    expect(
        engine.process(
            speedKmh: 20.1,
            isValid: true,
            roadSpeedLimit: null,
            bandIntervalKmh: 10),
        isNull);
    expect(
        engine
            .process(
                speedKmh: 20.2,
                isValid: true,
                roadSpeedLimit: null,
                bandIntervalKmh: 10)
            ?.message,
        '20 quilômetros por hora.');
  });

  test('anuncia somente a faixa mais próxima em saltos e confirma descida', () {
    final engine = SpeedAlertEngine();
    engine.process(speedKmh: 14, isValid: true, roadSpeedLimit: null);
    expect(engine.process(speedKmh: 26, isValid: true, roadSpeedLimit: null),
        isNull);
    expect(
        engine
            .process(speedKmh: 26.1, isValid: true, roadSpeedLimit: null)
            ?.message,
        '25 quilômetros por hora.');

    final descending = SpeedAlertEngine();
    descending.process(speedKmh: 26, isValid: true, roadSpeedLimit: null);
    expect(
        descending.process(speedKmh: 14, isValid: true, roadSpeedLimit: null),
        isNull);
    expect(
        descending
            .process(speedKmh: 13.9, isValid: true, roadSpeedLimit: null)
            ?.message,
        '15 quilômetros por hora.');
  });

  test('rearma excesso somente após retornar abaixo da margem', () {
    final engine = SpeedAlertEngine();
    engine.process(speedKmh: 40, isValid: true, roadSpeedLimit: 40);
    engine.process(speedKmh: 41, isValid: true, roadSpeedLimit: 40);
    expect(
        engine.process(speedKmh: 42, isValid: true, roadSpeedLimit: 40)?.kind,
        VoiceAlertKind.aboveLimit);
    engine.process(speedKmh: 38, isValid: true, roadSpeedLimit: 40);
    engine.process(speedKmh: 37, isValid: true, roadSpeedLimit: 40);
    engine.process(speedKmh: 41, isValid: true, roadSpeedLimit: 40);
    expect(
        engine.process(speedKmh: 42, isValid: true, roadSpeedLimit: 40)?.kind,
        VoiceAlertKind.aboveLimit);
  });

  test('rearma avisos relativos somente após duas leituras na margem', () {
    final engine = SpeedAlertEngine();
    engine.process(speedKmh: 40, isValid: true, roadSpeedLimit: 40);
    engine.process(speedKmh: 41, isValid: true, roadSpeedLimit: 40);
    engine.process(speedKmh: 42, isValid: true, roadSpeedLimit: 40);
    engine.process(speedKmh: 38, isValid: true, roadSpeedLimit: 40);
    engine.process(speedKmh: 38, isValid: true, roadSpeedLimit: 40);
    engine.process(speedKmh: 41, isValid: true, roadSpeedLimit: 40);
    expect(
        engine.process(speedKmh: 42, isValid: true, roadSpeedLimit: 40)?.kind,
        VoiceAlertKind.aboveLimit);
  });
}
