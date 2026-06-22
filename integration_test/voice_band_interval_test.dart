import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:speedometer/core/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('persiste a escolha de narração a cada 10 km/h', (tester) async {
    await tester.pumpWidget(const SpeedometerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limites e faixas de 5 km/h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A cada 10 km/h'));
    await tester.pumpAndSettle();

    expect(_intervalTile(tester).selected, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    expect(_intervalTile(tester).selected, isTrue);
  });
}

RadioListTile<int> _intervalTile(WidgetTester tester) =>
    tester.widget<RadioListTile<int>>(
      find.byWidgetPredicate(
        (widget) => widget is RadioListTile<int> && widget.value == 10,
      ),
    );
