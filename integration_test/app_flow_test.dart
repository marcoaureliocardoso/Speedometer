import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/core/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mantém o painel parado quando o consentimento é cancelado',
      (tester) async {
    await tester.pumpWidget(const SpeedometerApp());
    await tester.tap(find.text('Iniciar rastreamento'));
    await tester.pumpAndSettle();
    expect(find.text('Modo de dados'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Rastreamento parado'), findsOneWidget);
    expect(find.text('Iniciar rastreamento'), findsOneWidget);
  });
}
