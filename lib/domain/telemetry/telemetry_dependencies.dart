class TelemetrySample {
  const TelemetrySample({
    required this.latitude,
    required this.longitude,
    required this.speedMetersPerSecond,
    required this.speedAccuracy,
    this.horizontalAccuracy = 0,
    this.heading,
    this.headingAccuracy,
    this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double speedMetersPerSecond;
  final double speedAccuracy;
  final double horizontalAccuracy;
  final double? heading;
  final double? headingAccuracy;
  final DateTime? timestamp;
}

class HeadingSensorSample {
  const HeadingSensorSample({required this.degrees, required this.accuracy});

  final double degrees;
  final int accuracy;
}

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class RoadSegment {
  const RoadSegment({
    required this.id,
    required this.points,
    required this.tags,
  });

  final int id;
  final List<GeoPoint> points;
  final Map<String, String> tags;
}

class RoadMatch {
  const RoadMatch({
    required this.wayId,
    required this.limit,
    required this.name,
    required this.distanceMeters,
  });

  final int wayId;
  final int? limit;
  final String? name;
  final double distanceMeters;
}

enum LocationPermissionStatus { granted, denied, deniedForever }

abstract interface class LocationDataSource {
  Future<bool> isServiceEnabled();
  Future<LocationPermissionStatus> checkPermission();
  Future<LocationPermissionStatus> requestPermission();
  Future<void> openAppSettings();
  Future<void> openLocationSettings();
  Stream<TelemetrySample> get samples;
}

abstract interface class HeadingDataSource {
  Stream<HeadingSensorSample> get samples;

  Future<bool> isAvailable();

  Future<void> updateLocation(TelemetrySample sample);
}

abstract interface class RoadLimitDataSource {
  Future<List<RoadSegment>> fetchCandidates({
    required double latitude,
    required double longitude,
  });
  void dispose();
}

abstract interface class SpeechEngine {
  Future<bool> configure({required double volume, required double speechRate});
  Future<void> speak(String message);
  Future<void> stop();
}
