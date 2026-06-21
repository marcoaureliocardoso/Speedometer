import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/domain/telemetry/telemetry_dependencies.dart';
import 'package:speedometer/presentation/controllers/telemetry_controller.dart';

void main() {
  test('não inicia quando a permissão é negada', () async {
    final controller = TelemetryController(
      location:
          _FakeLocation(permission: LocationPermissionStatus.deniedForever),
      roadLimit: _FakeRoadLimit(),
      speech: _FakeSpeech(),
    );
    await controller.start(
        allowOnline: false, announceLimits: true, announceBands: false);
    expect(controller.status, TrackingStatus.permissionDeniedForever);
  });

  test('atualiza velocidade e consulta limite online', () async {
    final location = _FakeLocation();
    final road = _FakeRoadLimit(limit: 60);
    final controller = TelemetryController(
        location: location, roadLimit: road, speech: _FakeSpeech());
    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    final now = DateTime.now();
    location.emit(TelemetrySample(
        latitude: -23.5,
        longitude: -46.6,
        speedMetersPerSecond: 10,
        speedAccuracy: 1,
        horizontalAccuracy: 5,
        heading: 90,
        headingAccuracy: 5,
        timestamp: now));
    await Future<void>.delayed(Duration.zero);
    location.emit(TelemetrySample(
        latitude: -23.5,
        longitude: -46.6,
        speedMetersPerSecond: 10,
        speedAccuracy: 1,
        horizontalAccuracy: 5,
        heading: 90,
        headingAccuracy: 5,
        timestamp: now.add(const Duration(seconds: 1))));
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, TrackingStatus.active);
    expect(controller.speedKmh, 36);
    expect(controller.roadSpeedLimit, 60);
    expect(road.calls, 1);
    await controller.stop();
  });
}

class _FakeLocation implements LocationDataSource {
  _FakeLocation({this.permission = LocationPermissionStatus.granted});
  final LocationPermissionStatus permission;
  final _controller = StreamController<TelemetrySample>();
  void emit(TelemetrySample sample) => _controller.add(sample);
  @override
  Future<bool> isServiceEnabled() async => true;
  @override
  Future<LocationPermissionStatus> checkPermission() async => permission;
  @override
  Future<LocationPermissionStatus> requestPermission() async => permission;
  @override
  Stream<TelemetrySample> get samples => _controller.stream;
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> openLocationSettings() async {}
}

class _FakeRoadLimit implements RoadLimitDataSource {
  _FakeRoadLimit({this.limit});
  final int? limit;
  int calls = 0;
  @override
  Future<List<RoadSegment>> fetchCandidates(
      {required double latitude, required double longitude}) async {
    calls++;
    if (limit == null) return const [];
    return [
      RoadSegment(
        id: 1,
        points: const [GeoPoint(-23.5, -46.6002), GeoPoint(-23.5, -46.5998)],
        tags: {'maxspeed': '$limit'},
      ),
    ];
  }

  @override
  void dispose() {}
}

class _FakeSpeech implements SpeechEngine {
  @override
  Future<bool> configure({required double volume, required double speechRate}) async => true;
  @override
  Future<void> speak(String message) async {}
  @override
  Future<void> stop() async {}
}
