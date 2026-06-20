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
    expect(controller.status, TrackingStatus.permissionDenied);
  });

  test('atualiza velocidade e consulta limite online', () async {
    final location = _FakeLocation();
    final road = _FakeRoadLimit(limit: 60);
    final controller = TelemetryController(
        location: location, roadLimit: road, speech: _FakeSpeech());
    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    location.emit(const TelemetrySample(
        latitude: -23.5,
        longitude: -46.6,
        speedMetersPerSecond: 10,
        speedAccuracy: 1));
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
}

class _FakeRoadLimit implements RoadLimitDataSource {
  _FakeRoadLimit({this.limit});
  final int? limit;
  int calls = 0;
  @override
  Future<int?> fetchLimit(
      {required double latitude, required double longitude}) async {
    calls++;
    return limit;
  }

  @override
  void dispose() {}
}

class _FakeSpeech implements SpeechEngine {
  @override
  Future<void> configure() async {}
  @override
  Future<void> speak(String message) async {}
  @override
  Future<void> stop() async {}
}
