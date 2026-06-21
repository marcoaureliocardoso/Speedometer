import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/presentation/widgets/speedometer_gauge.dart';

void main() {
  testWidgets('não representa velocidade zero quando o limite é desconhecido',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SpeedometerGauge(speed: 72, roadSpeedLimit: null)),
    ));
    expect(find.text('Escala disponível após a confirmação do limite'), findsOneWidget);
    expect(find.bySemanticsLabel('Limite indisponível. Escala do medidor indisponível.'),
        findsOneWidget);
  });

  testWidgets('expõe excesso de limite na semântica do medidor', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SpeedometerGauge(speed: 65, roadSpeedLimit: 60)),
    ));
    expect(
      find.bySemanticsLabel(
          'Velocidade 65 quilômetros por hora. Limite 60 quilômetros por hora. Acima do limite.'),
      findsOneWidget,
    );
  });
}
