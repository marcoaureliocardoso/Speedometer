import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:speedometer/core/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'mantém rastreamento online quando o sensor nativo é indisponível',
      (tester) async {
    await tester.pumpWidget(const SpeedometerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online e offline'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Iniciar rastreamento'));
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Rastreamento ativo'), findsOneWidget);
    await tester.tap(find.text('Encerrar rastreamento'));
    await tester.pumpAndSettle();
  });
}
