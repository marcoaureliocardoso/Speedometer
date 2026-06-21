import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:speedometer/core/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('explica a negativa permanente de localização', (tester) async {
    await tester.pumpWidget(const SpeedometerApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Iniciar rastreamento'));
    await tester.pump(const Duration(milliseconds: 500));
    if (find.text('Modo de dados').evaluate().isNotEmpty) {
      await tester.tap(find.text('Somente offline').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continuar'));
    }
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('A permissão de localização foi negada permanentemente.'),
        findsOneWidget);
    expect(find.text('Abrir configurações do Android'), findsOneWidget);
    expect(find.text('Iniciar rastreamento'), findsOneWidget);
  });
}
