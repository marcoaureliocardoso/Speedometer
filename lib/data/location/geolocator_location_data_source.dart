import 'package:geolocator/geolocator.dart';

import '../../domain/telemetry/telemetry_dependencies.dart';

class GeolocatorLocationDataSource implements LocationDataSource {
  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      _mapPermission(await Geolocator.checkPermission());

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      _mapPermission(await Geolocator.requestPermission());

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Stream<TelemetrySample> get samples => Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
          intervalDuration: Duration(seconds: 1),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: 'Speedometer em rastreamento',
            notificationText: 'Monitorando velocidade por GPS.',
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      ).map(
        (position) => TelemetrySample(
          latitude: position.latitude,
          longitude: position.longitude,
          speedMetersPerSecond: position.speed,
          speedAccuracy: position.speedAccuracy,
          horizontalAccuracy: position.accuracy,
          heading: position.heading.isNaN ? null : position.heading,
          headingAccuracy:
              position.headingAccuracy.isNaN ? null : position.headingAccuracy,
          timestamp: position.timestamp,
        ),
      );

  LocationPermissionStatus _mapPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.deniedForever =>
        LocationPermissionStatus.deniedForever,
      LocationPermission.denied => LocationPermissionStatus.denied,
      _ => LocationPermissionStatus.granted,
    };
  }
}
