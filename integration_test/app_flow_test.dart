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

  testWidgets('inicia, mostra estado de condução e encerra rastreamento',
      (tester) async {
    await tester.pumpWidget(const SpeedometerApp());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Iniciar rastreamento'));
    await tester.pump(const Duration(milliseconds: 500));
    if (find.text('Modo de dados').evaluate().isNotEmpty) {
      await tester.tap(find.text('Somente offline').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continuar'));
    }
    await tester.pump(const Duration(seconds: 6));

    expect(find.text('Rastreamento ativo'), findsOneWidget);
    expect(find.text('Encerrar rastreamento'), findsOneWidget);
    expect(find.byTooltip('Configurações'), findsNothing);
    expect(find.byTooltip('Regiões offline'), findsNothing);

    await tester.tap(find.text('Encerrar rastreamento'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Rastreamento parado'), findsOneWidget);
    expect(find.text('Iniciar rastreamento'), findsOneWidget);
  });
}
