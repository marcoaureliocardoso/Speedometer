import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  static const _voiceModeKey = 'voice_mode';
  static const _volumeKey = 'voice_volume';
  static const _speechRateKey = 'voice_rate';
  static const _bandIntervalKey = 'voice_band_interval_kmh';
  static const _customSpeedLimitKey = 'custom_speed_limit_kmh';
  static const _dataModeKey = 'data_mode';

  Future<StoredSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return StoredSettings(
      voiceModeIndex: preferences.getInt(_voiceModeKey) ?? 1,
      volume: preferences.getDouble(_volumeKey) ?? 1,
      speechRate: preferences.getDouble(_speechRateKey) ?? 1,
      bandIntervalKmh: preferences.getInt(_bandIntervalKey) ?? 5,
      customSpeedLimitKmh: preferences.getInt(_customSpeedLimitKey),
      dataMode: preferences.getString(_dataModeKey),
    );
  }

  Future<void> save({
    required int voiceModeIndex,
    required double volume,
    required double speechRate,
    int bandIntervalKmh = 5,
    int? customSpeedLimitKmh,
    required String? dataMode,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_voiceModeKey, voiceModeIndex);
    await preferences.setDouble(_volumeKey, volume);
    await preferences.setDouble(_speechRateKey, speechRate);
    await preferences.setInt(_bandIntervalKey, bandIntervalKmh == 10 ? 10 : 5);
    if (customSpeedLimitKmh == null) {
      await preferences.remove(_customSpeedLimitKey);
    } else {
      await preferences.setInt(_customSpeedLimitKey, customSpeedLimitKmh);
    }
    if (dataMode == null) {
      await preferences.remove(_dataModeKey);
    } else {
      await preferences.setString(_dataModeKey, dataMode);
    }
  }
}

class StoredSettings {
  const StoredSettings({
    required this.voiceModeIndex,
    required this.volume,
    required this.speechRate,
    required this.bandIntervalKmh,
    required this.customSpeedLimitKmh,
    required this.dataMode,
  });

  final int voiceModeIndex;
  final double volume;
  final double speechRate;
  final int bandIntervalKmh;
  final int? customSpeedLimitKmh;
  final String? dataMode;
}
