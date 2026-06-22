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
    expect(controller.roadName, 'Via de teste');
    expect(road.calls, 1);
    await controller.stop();
  });

  test('anuncia o limite ao confirmar uma nova via mesmo com o mesmo valor',
      () async {
    var now = DateTime(2026, 1, 1, 12);
    final location = _FakeLocation();
    final speech = _FakeSpeech();
    final controller = TelemetryController(
      location: location,
      roadLimit: _SequentialRoadLimit(),
      speech: speech,
      clock: () => now,
    );

    await controller.start(
        allowOnline: true,
        announceLimits: true,
        announceBands: false,
        bandIntervalKmh: 10);
    location.emit(_validSample(timestamp: now));
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 1));
    location.emit(_validSample(timestamp: now));
    await Future<void>.delayed(Duration.zero);

    now = now.add(const Duration(seconds: 10));
    location.emit(_validSample(timestamp: now, longitude: -46.5995));
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 1));
    location.emit(_validSample(timestamp: now, longitude: -46.5995));
    await Future<void>.delayed(Duration.zero);

    expect(
      speech.messages,
      [
        'Atenção: Novo limite de velocidade: 60 quilômetros por hora.',
        'Atenção: Novo limite de velocidade: 60 quilômetros por hora.',
      ],
    );
    await controller.stop();
  });

  test('usa 10 km/h somente para anúncios da velocidade atual', () async {
    final location = _FakeLocation();
    final speech = _FakeSpeech();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(),
      speech: speech,
    );

    await controller.start(
        allowOnline: false,
        announceLimits: false,
        announceBands: true,
        bandIntervalKmh: 10);
    for (final speedKmh in [14.9, 15.1, 20.1, 20.2]) {
      location.emit(_validSample(
          speedMetersPerSecond: speedKmh / 3.6, timestamp: DateTime.now()));
      await Future<void>.delayed(Duration.zero);
    }

    expect(speech.messages, ['20 quilômetros por hora.']);
    await controller.stop();
  });

  test('anuncia o limite confirmado durante a inicialização da voz', () async {
    final voiceConfigured = Completer<bool>();
    final location = _FakeLocation();
    final speech = _FakeSpeech(configureCompleter: voiceConfigured);
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(limit: 60),
      speech: speech,
    );

    final start = controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    await Future<void>.delayed(Duration.zero);
    final now = DateTime.now();
    location.emit(_validSample(timestamp: now));
    await Future<void>.delayed(Duration.zero);
    location.emit(_validSample(timestamp: now.add(const Duration(seconds: 1))));
    await Future<void>.delayed(Duration.zero);
    expect(speech.messages, isEmpty);

    voiceConfigured.complete(true);
    await start;
    await Future<void>.delayed(Duration.zero);

    expect(speech.messages,
        ['Atenção: Novo limite de velocidade: 60 quilômetros por hora.']);
    await controller.stop();
  });

  test('marca localização desatualizada e se recupera com nova amostra',
      () async {
    var now = DateTime(2026, 1, 1, 12);
    final location = _FakeLocation();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(),
      speech: _FakeSpeech(),
      clock: () => now,
      staleAfter: const Duration(seconds: 1),
      limitExpiryAfter: const Duration(seconds: 2),
      staleCheckInterval: const Duration(milliseconds: 10),
    );
    await controller.start(
        allowOnline: false, announceLimits: true, announceBands: false);
    location.emit(TelemetrySample(
      latitude: -23.5,
      longitude: -46.6,
      speedMetersPerSecond: 10,
      speedAccuracy: 1,
      timestamp: now,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    now = now.add(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.degradationReasons,
        contains(TelemetryDegradedReason.locationStale));

    location.emit(TelemetrySample(
      latitude: -23.5,
      longitude: -46.6,
      speedMetersPerSecond: 10,
      speedAccuracy: 1,
      timestamp: now,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.degradationReasons,
        isNot(contains(TelemetryDegradedReason.locationStale)));
    await controller.stop();
  });

  test('mantém o painel em modo visual quando TTS pt-BR não está disponível',
      () async {
    final controller = TelemetryController(
      location: _FakeLocation(),
      roadLimit: _FakeRoadLimit(),
      speech: _FakeSpeech(ttsAvailable: false),
    );

    await controller.start(
        allowOnline: false, announceLimits: true, announceBands: false);

    expect(controller.degradationReasons,
        contains(TelemetryDegradedReason.ttsUnavailable));
    await controller.stop();
  });

  test('inicia a captura de GPS sem aguardar a configuração de voz', () async {
    final voiceConfigured = Completer<bool>();
    final location = _FakeLocation();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(),
      speech: _FakeSpeech(configureCompleter: voiceConfigured),
    );

    final start = controller.start(
        allowOnline: false, announceLimits: true, announceBands: false);
    await Future<void>.delayed(Duration.zero);
    location.emit(_validSample());
    await Future<void>.delayed(Duration.zero);

    expect(controller.speedKmh, 36);
    voiceConfigured.complete(true);
    await start;
    await controller.stop();
  });

  test('registra a latência da amostra de localização', () async {
    final now = DateTime(2026, 1, 1, 12);
    final location = _FakeLocation();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(),
      speech: _FakeSpeech(),
      clock: () => now,
    );

    await controller.start(
        allowOnline: false, announceLimits: true, announceBands: false);
    location.emit(_validSample(
        timestamp: now.subtract(const Duration(milliseconds: 250))));
    await Future<void>.delayed(Duration.zero);

    expect(controller.lastLocationReceivedAt, now);
    expect(controller.lastLocationLatency, const Duration(milliseconds: 250));
    await controller.stop();
  });

  test('não consulta a via quando o modo online está desativado', () async {
    final location = _FakeLocation();
    final road = _FakeRoadLimit(limit: 60);
    final controller = TelemetryController(
        location: location, roadLimit: road, speech: _FakeSpeech());

    await controller.start(
        allowOnline: false, announceLimits: true, announceBands: false);
    location.emit(_validSample());
    await Future<void>.delayed(Duration.zero);

    expect(road.calls, 0);
    expect(controller.roadSpeedLimit, isNull);
    expect(controller.roadName, isNull);
    expect(controller.degradationReasons,
        contains(TelemetryDegradedReason.onlineDataDisabled));
    await controller.stop();
  });

  test('marca via não confirmada quando a consulta não encontra candidatos',
      () async {
    final location = _FakeLocation();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(),
      speech: _FakeSpeech(),
    );

    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    location.emit(_validSample());
    await Future<void>.delayed(Duration.zero);

    expect(controller.roadSpeedLimit, isNull);
    expect(controller.roadName, isNull);
    expect(controller.degradationReasons,
        contains(TelemetryDegradedReason.roadMatchLowConfidence));
    await controller.stop();
  });

  test('mantém o nome da via apenas até a expiração da localização', () async {
    var now = DateTime(2026, 1, 1, 12);
    final location = _FakeLocation();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(limit: 60),
      speech: _FakeSpeech(),
      clock: () => now,
      staleAfter: const Duration(seconds: 1),
      limitExpiryAfter: const Duration(seconds: 2),
      staleCheckInterval: const Duration(milliseconds: 10),
    );

    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    location.emit(_validSample(timestamp: now));
    await Future<void>.delayed(Duration.zero);
    location.emit(_validSample(timestamp: now.add(const Duration(seconds: 1))));
    await Future<void>.delayed(Duration.zero);
    expect(controller.roadName, 'Via de teste');

    now = now.add(const Duration(seconds: 4));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.roadSpeedLimit, isNull);
    expect(controller.roadName, isNull);
    expect(controller.roadWayId, isNull);
    await controller.stop();
  });
}

TelemetrySample _validSample({
  DateTime? timestamp,
  double latitude = -23.5,
  double longitude = -46.6,
  double speedMetersPerSecond = 10,
}) =>
    TelemetrySample(
      latitude: latitude,
      longitude: longitude,
      speedMetersPerSecond: speedMetersPerSecond,
      speedAccuracy: 1,
      horizontalAccuracy: 5,
      heading: 90,
      headingAccuracy: 5,
      timestamp: timestamp ?? DateTime.now(),
    );

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
        tags: {'maxspeed': '$limit', 'name': 'Via de teste'},
      ),
    ];
  }

  @override
  void dispose() {}
}

class _SequentialRoadLimit implements RoadLimitDataSource {
  var _nextWayId = 1;

  @override
  Future<List<RoadSegment>> fetchCandidates(
      {required double latitude, required double longitude}) async {
    final wayId = _nextWayId++;
    return [
      RoadSegment(
        id: wayId,
        points: [
          GeoPoint(latitude, longitude - .0002),
          GeoPoint(latitude, longitude + .0002),
        ],
        tags: const {'maxspeed': '60'},
      ),
    ];
  }

  @override
  void dispose() {}
}

class _FakeSpeech implements SpeechEngine {
  _FakeSpeech({this.ttsAvailable = true, this.configureCompleter});
  final bool ttsAvailable;
  final Completer<bool>? configureCompleter;
  final List<String> messages = [];
  @override
  Future<bool> configure(
          {required double volume, required double speechRate}) =>
      configureCompleter?.future ?? Future.value(ttsAvailable);
  @override
  Future<void> speak(String message) async => messages.add(message);
  @override
  Future<void> stop() async {}
}
