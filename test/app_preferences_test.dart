import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speedometer/data/preferences/app_preferences.dart';

void main() {
  test('persiste e recupera as escolhas de voz e dados', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = AppPreferences();

    await preferences.save(
      voiceModeIndex: 2,
      volume: .65,
      speechRate: 1.2,
      bandIntervalKmh: 10,
      customSpeedLimitKmh: 80,
      dataMode: 'Online e offline',
    );
    final saved = await preferences.load();

    expect(saved.voiceModeIndex, 2);
    expect(saved.volume, .65);
    expect(saved.speechRate, 1.2);
    expect(saved.bandIntervalKmh, 10);
    expect(saved.customSpeedLimitKmh, 80);
    expect(saved.dataMode, 'Online e offline');
  });

  test('remove o limite personalizado quando a configuração é limpa', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = AppPreferences();

    await preferences.save(
      voiceModeIndex: 1,
      volume: 1,
      speechRate: 1,
      customSpeedLimitKmh: 80,
      dataMode: null,
    );
    await preferences.save(
      voiceModeIndex: 1,
      volume: 1,
      speechRate: 1,
      customSpeedLimitKmh: null,
      dataMode: null,
    );

    expect((await preferences.load()).customSpeedLimitKmh, isNull);
  });
}
