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
      dataMode: 'Online e offline',
    );
    final saved = await preferences.load();

    expect(saved.voiceModeIndex, 2);
    expect(saved.volume, .65);
    expect(saved.speechRate, 1.2);
    expect(saved.dataMode, 'Online e offline');
  });
}
