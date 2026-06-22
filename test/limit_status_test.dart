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
            degradationReasons: {TelemetryDegradedReason.gpsWeak},
            speedKmh: 50,
          ),
        ),
      ),
    );

    expect(find.textContaining('Via atual:'), findsNothing);
    expect(find.text('GPS com baixa precisão'), findsOneWidget);
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
    expect(find.text('GPS com baixa precisão'), findsNothing);
  });
}
