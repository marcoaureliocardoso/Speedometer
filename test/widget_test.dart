import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/core/app.dart';

void main() {
  testWidgets('exibe o painel inicial', (tester) async {
    await tester.pumpWidget(const SpeedometerApp());

    expect(find.text('0'), findsOneWidget);
    expect(find.text('Limite indisponível'), findsOneWidget);
  });
}
