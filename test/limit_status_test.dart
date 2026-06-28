import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/presentation/controllers/telemetry_controller.dart';
import 'package:speedometer/presentation/pages/dashboard_page.dart';

void main() {
  testWidgets('mostra o nome da via confirmada no dashboard', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LimitStatus(
            isTracking: true,
            roadSpeedLimit: 60,
            roadName: 'Avenida de teste',
            degradationReasons: {},
            speedKmh: 50,
          ),
        ),
      ),
    );

    expect(find.text('Via atual: Avenida de teste'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
          'Limite: 60 quilômetros por hora. Via atual: Avenida de teste.'),
      findsOneWidget,
    );
  });

  testWidgets('não reserva espaço quando a via não possui nome',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LimitStatus(
            isTracking: true,
            roadSpeedLimit: 60,
            roadName: '  ',
            degradationReasons: {TelemetryDegradedReason.positionWeak},
            speedKmh: 50,
          ),
        ),
      ),
    );

    expect(find.textContaining('Via atual:'), findsNothing);
    expect(find.text('Posição GPS com baixa precisão'), findsOneWidget);
  });

  testWidgets('explica quando a direção não confirma a via', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LimitStatus(
            isTracking: true,
            roadSpeedLimit: null,
            roadName: null,
            degradationReasons: {TelemetryDegradedReason.headingWeak},
            speedKmh: 50,
          ),
        ),
      ),
    );

    expect(
        find.text('Direção insuficiente para confirmar a via'), findsOneWidget);
    expect(find.text('Posição GPS com baixa precisão'), findsNothing);
  });

  testWidgets('mostra via atual mesmo sem limite', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LimitStatus(
            isTracking: true,
            roadSpeedLimit: null,
            roadName: 'Rua sem limite',
            degradationReasons: {},
            speedKmh: 30,
          ),
        ),
      ),
    );

    expect(find.text('Limite indisponível'), findsOneWidget);
    expect(find.text('Via atual: Rua sem limite'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Limite indisponível. Via atual: Rua sem limite.'),
      findsOneWidget,
    );
  });

  testWidgets('distingue posição e velocidade imprecisas', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LimitStatus(
            isTracking: true,
            roadSpeedLimit: null,
            roadName: null,
            degradationReasons: {
              TelemetryDegradedReason.positionWeak,
              TelemetryDegradedReason.speedWeak,
            },
            speedKmh: 30,
          ),
        ),
      ),
    );

    expect(find.text('Posição GPS com baixa precisão'), findsOneWidget);
    expect(find.text('Velocidade GPS com baixa precisão'), findsOneWidget);
  });
}
