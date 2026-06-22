import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:speedometer/core/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('persiste e remove o limite personalizado entre inicializações',
      (tester) async {
    await tester.pumpWidget(const SpeedometerApp());
    await tester.pumpAndSettle();

    await _openSettings(tester);
    await tester.enterText(find.byType(TextField), '80');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _restartApp(tester);
    await _openSettings(tester);
    expect(_customLimitField(tester).controller!.text, '80');

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _restartApp(tester);
    await _openSettings(tester);
    expect(_customLimitField(tester).controller!.text, isEmpty);
  });
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Configurações'));
  await tester.pumpAndSettle();
}

Future<void> _restartApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SpeedometerApp());
  await tester.pumpAndSettle();
}

TextField _customLimitField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));
