import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/core/app.dart';

void main() {
  testWidgets('exibe o painel inicial', (tester) async {
    await tester.pumpWidget(const SpeedometerApp());

    expect(find.text('0'), findsOneWidget);
    expect(find.text('Limite indisponível'), findsOneWidget);
    expect(find.text('Iniciar rastreamento'), findsOneWidget);
    expect(find.text('Escala disponível após a confirmação do limite'),
        findsOneWidget);
  });

  testWidgets('solicita o modo de dados antes de iniciar o rastreamento',
      (tester) async {
    await tester.pumpWidget(const SpeedometerApp());

    await tester.tap(find.text('Iniciar rastreamento'));
    await tester.pumpAndSettle();

    expect(find.text('Modo de dados'), findsOneWidget);
    expect(find.text('Somente offline'), findsWidgets);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Rastreamento parado'), findsOneWidget);
  });

  testWidgets('mantém ações e estados essenciais visíveis em retrato',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SpeedometerApp());

    expect(find.text('Rastreamento parado'), findsOneWidget);
    expect(find.text('Limite indisponível'), findsOneWidget);
    expect(find.text('Iniciar rastreamento'), findsOneWidget);
  });

  testWidgets(
      'expõe configurações e o estado vazio de regiões fora do rastreamento',
      (tester) async {
    await tester.pumpWidget(const SpeedometerApp());

    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    expect(find.text('Alertas de voz'), findsOneWidget);
    expect(find.text('Limites apenas'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Regiões offline'));
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma região offline'), findsOneWidget);
  });
}
