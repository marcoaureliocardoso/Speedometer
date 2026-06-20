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
  Stream<TelemetrySample> get samples => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
        ),
      ).map(
        (position) => TelemetrySample(
          latitude: position.latitude,
          longitude: position.longitude,
          speedMetersPerSecond: position.speed,
          speedAccuracy: position.speedAccuracy,
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
