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
}
