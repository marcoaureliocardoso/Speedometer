import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/presentation/pages/settings_page.dart';

void main() {
  testWidgets('atualiza o intervalo de narração para 10 km/h', (tester) async {
    VoiceSettings? updated;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settings: const VoiceSettings(mode: VoiceMode.limitsAndBands),
          dataMode: 'Somente offline',
          onChanged: (settings) => updated = settings,
          onDataModeChanged: (_) {},
          onPreview: (_) async {},
        ),
      ),
    );

    await tester.tap(find.text('A cada 10 km/h'));
    await tester.pumpAndSettle();

    expect(updated?.bandIntervalKmh, 10);
  });

  testWidgets('aceita e remove o limite personalizado', (tester) async {
    VoiceSettings? updated;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settings: const VoiceSettings(),
          dataMode: 'Somente offline',
          onChanged: (settings) => updated = settings,
          onDataModeChanged: (_) {},
          onPreview: (_) async {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '80');
    await tester.pump();
    expect(updated?.customSpeedLimitKmh, 80);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(updated?.customSpeedLimitKmh, isNull);
  });

  testWidgets('rejeita limites personalizados fora do intervalo permitido',
      (tester) async {
    VoiceSettings? updated;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settings: const VoiceSettings(),
          dataMode: 'Somente offline',
          onChanged: (settings) => updated = settings,
          onDataModeChanged: (_) {},
          onPreview: (_) async {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    expect(find.text('Informe um valor entre 1 e 300 km/h.'), findsOneWidget);
    expect(updated, isNull);

    await tester.enterText(find.byType(TextField), '301');
    await tester.pump();
    expect(find.text('Informe um valor entre 1 e 300 km/h.'), findsOneWidget);
    expect(updated, isNull);
  });
}
