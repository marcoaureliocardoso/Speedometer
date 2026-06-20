class TelemetrySample {
  const TelemetrySample({
    required this.latitude,
    required this.longitude,
    required this.speedMetersPerSecond,
    required this.speedAccuracy,
  });

  final double latitude;
  final double longitude;
  final double speedMetersPerSecond;
  final double speedAccuracy;
}

enum LocationPermissionStatus { granted, denied, deniedForever }

abstract interface class LocationDataSource {
  Future<bool> isServiceEnabled();
  Future<LocationPermissionStatus> checkPermission();
  Future<LocationPermissionStatus> requestPermission();
  Stream<TelemetrySample> get samples;
}

abstract interface class RoadLimitDataSource {
  Future<int?> fetchLimit(
      {required double latitude, required double longitude});
  void dispose();
}

abstract interface class SpeechEngine {
  Future<void> configure();
  Future<void> speak(String message);
  Future<void> stop();
}
