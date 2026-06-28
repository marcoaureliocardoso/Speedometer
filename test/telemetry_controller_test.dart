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

  test('narra quando o limite personalizado é ultrapassado', () async {
    final location = _FakeLocation();
    final speech = _FakeSpeech();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(),
      speech: speech,
    );

    await controller.start(
      allowOnline: false,
      announceLimits: true,
      announceBands: false,
      customSpeedLimitKmh: 80,
    );
    for (final speedKmh in [80.0, 81.0, 82.0]) {
      location.emit(_validSample(
          speedMetersPerSecond: speedKmh / 3.6, timestamp: DateTime.now()));
      await Future<void>.delayed(Duration.zero);
    }

    expect(speech.messages, ['Limite de velocidade 80Km/h ultrapassado.']);
    await controller.stop();
  });

  test('respeita o modo silencioso para o limite personalizado', () async {
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
      announceBands: false,
      customSpeedLimitKmh: 80,
    );
    for (final speedKmh in [80.0, 81.0, 82.0]) {
      location.emit(_validSample(
          speedMetersPerSecond: speedKmh / 3.6, timestamp: DateTime.now()));
      await Future<void>.delayed(Duration.zero);
    }

    expect(speech.messages, isEmpty);
    await controller.stop();
  });

  test('não suprime o limite personalizado após anunciar o limite da via',
      () async {
    var now = DateTime(2026, 1, 1, 12);
    final location = _FakeLocation();
    final speech = _FakeSpeech();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(limit: 60),
      speech: speech,
      clock: () => now,
    );

    await controller.start(
      allowOnline: true,
      announceLimits: true,
      announceBands: false,
      customSpeedLimitKmh: 80,
    );
    for (final speedKmh in [79.0, 81.0, 82.0]) {
      location.emit(
          _validSample(speedMetersPerSecond: speedKmh / 3.6, timestamp: now));
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 1));
    }

    expect(
        speech.messages, contains('Limite de velocidade 80Km/h ultrapassado.'));
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

  test('distingue direção imprecisa de GPS com baixa precisão', () async {
    final location = _FakeLocation();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(),
      speech: _FakeSpeech(),
    );

    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    location.emit(TelemetrySample(
      latitude: -23.5,
      longitude: -46.6,
      speedMetersPerSecond: 10,
      speedAccuracy: 1,
      horizontalAccuracy: 5,
      heading: 90,
      headingAccuracy: 30,
      timestamp: DateTime.now(),
    ));
    await Future<void>.delayed(Duration.zero);

    expect(controller.degradationReasons,
        contains(TelemetryDegradedReason.headingWeak));
    expect(controller.degradationReasons,
        isNot(contains(TelemetryDegradedReason.positionWeak)));

    location.emit(_validSample());
    await Future<void>.delayed(Duration.zero);
    expect(controller.degradationReasons,
        isNot(contains(TelemetryDegradedReason.headingWeak)));
    await controller.stop();
  });

  test('estima a direção pelo deslocamento quando o rumo reportado é impreciso',
      () async {
    var now = DateTime(2026, 1, 1, 12);
    final location = _FakeLocation();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(limit: 60),
      speech: _FakeSpeech(),
      clock: () => now,
    );

    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    location
        .emit(_sampleWithImpreciseHeading(longitude: -46.6002, timestamp: now));
    await Future<void>.delayed(Duration.zero);

    now = now.add(const Duration(seconds: 2));
    location
        .emit(_sampleWithImpreciseHeading(longitude: -46.5999, timestamp: now));
    await Future<void>.delayed(Duration.zero);

    now = now.add(const Duration(seconds: 1));
    location.emit(
        _sampleWithImpreciseHeading(longitude: -46.59985, timestamp: now));
    await Future<void>.delayed(Duration.zero);

    expect(controller.roadSpeedLimit, 60);
    expect(controller.degradationReasons,
        isNot(contains(TelemetryDegradedReason.headingWeak)));
    await controller.stop();
  });

  test('usa a orientação do sensor para confirmar a via em baixa velocidade',
      () async {
    var now = DateTime(2026, 1, 1, 12);
    final location = _FakeLocation();
    final heading = _FakeHeading();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(limit: 60),
      speech: _FakeSpeech(),
      heading: heading,
      clock: () => now,
    );

    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    heading.emit(const HeadingSensorSample(degrees: 90, accuracy: 3));
    await Future<void>.delayed(Duration.zero);
    location.emit(_sampleWithImpreciseHeading(
        longitude: -46.6, timestamp: now, speedMetersPerSecond: 2));
    await Future<void>.delayed(Duration.zero);

    now = now.add(const Duration(seconds: 1));
    location.emit(_sampleWithImpreciseHeading(
        longitude: -46.6, timestamp: now, speedMetersPerSecond: 2));
    await Future<void>.delayed(Duration.zero);

    expect(controller.roadSpeedLimit, 60);
    expect(controller.degradationReasons,
        isNot(contains(TelemetryDegradedReason.headingWeak)));
    expect(heading.locationUpdates, hasLength(2));
    await controller.stop();
  });

  test('usa distância quando o sensor tem calibração insuficiente', () async {
    final location = _FakeLocation();
    final heading = _FakeHeading();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(limit: 60),
      speech: _FakeSpeech(),
      heading: heading,
    );

    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    heading.emit(const HeadingSensorSample(degrees: 90, accuracy: 2));
    await Future<void>.delayed(Duration.zero);
    location.emit(_sampleWithImpreciseHeading(
        longitude: -46.6, timestamp: DateTime.now(), speedMetersPerSecond: 2));
    await Future<void>.delayed(Duration.zero);

    expect(controller.roadSpeedLimit, isNull);
    expect(controller.degradationReasons,
        isNot(contains(TelemetryDegradedReason.headingWeak)));
    await controller.stop();
  });

  test('usa distância quando a orientação está desatualizada', () async {
    var now = DateTime(2026, 1, 1, 12);
    final location = _FakeLocation();
    final heading = _FakeHeading();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(limit: 60),
      speech: _FakeSpeech(),
      heading: heading,
      clock: () => now,
    );

    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    heading.emit(const HeadingSensorSample(degrees: 90, accuracy: 3));
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 2));
    location.emit(_sampleWithImpreciseHeading(
        longitude: -46.6, timestamp: now, speedMetersPerSecond: 2));
    await Future<void>.delayed(Duration.zero);

    expect(controller.roadSpeedLimit, isNull);
    expect(controller.degradationReasons,
        isNot(contains(TelemetryDegradedReason.headingWeak)));
    await controller.stop();
  });

  test('mantém rastreamento quando o sensor de orientação é indisponível',
      () async {
    final location = _FakeLocation();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(),
      speech: _FakeSpeech(),
      heading: _FakeHeading(available: false),
    );

    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    location.emit(_validSample());
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, TrackingStatus.active);
    await controller.stop();
  });

  test('usa distância sem sensor em velocidade de condução', () async {
    final location = _FakeLocation();
    final heading = _FakeHeading();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(limit: 60),
      speech: _FakeSpeech(),
      heading: heading,
    );

    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    heading.emit(const HeadingSensorSample(degrees: 90, accuracy: 3));
    await Future<void>.delayed(Duration.zero);
    location.emit(_sampleWithImpreciseHeading(
        longitude: -46.6, timestamp: DateTime.now(), speedMetersPerSecond: 12));
    await Future<void>.delayed(Duration.zero);

    expect(controller.roadSpeedLimit, isNull);
    expect(controller.degradationReasons,
        isNot(contains(TelemetryDegradedReason.headingWeak)));
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

  test('confirma via sem limite e com velocidade imprecisa', () async {
    final location = _FakeLocation();
    final controller = TelemetryController(
      location: location,
      roadLimit: _FakeRoadLimit(name: 'Rua sem limite'),
      speech: _FakeSpeech(),
    );

    await controller.start(
        allowOnline: true, announceLimits: true, announceBands: false);
    final now = DateTime.now();
    location.emit(_validSample(timestamp: now, speedAccuracy: 4));
    await Future<void>.delayed(Duration.zero);
    location.emit(_validSample(
      timestamp: now.add(const Duration(seconds: 2)),
      longitude: -46.59999,
      speedAccuracy: 4,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(controller.roadName, 'Rua sem limite');
    expect(controller.roadSpeedLimit, isNull);
    expect(controller.degradationReasons,
        contains(TelemetryDegradedReason.speedWeak));
    expect(controller.degradationReasons,
        isNot(contains(TelemetryDegradedReason.positionWeak)));
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
  double speedAccuracy = 1,
}) =>
    TelemetrySample(
      latitude: latitude,
      longitude: longitude,
      speedMetersPerSecond: speedMetersPerSecond,
      speedAccuracy: speedAccuracy,
      horizontalAccuracy: 5,
      heading: 90,
      headingAccuracy: 5,
      timestamp: timestamp ?? DateTime.now(),
    );

TelemetrySample _sampleWithImpreciseHeading({
  required double longitude,
  required DateTime timestamp,
  double speedMetersPerSecond = 10,
}) =>
    TelemetrySample(
      latitude: -23.5,
      longitude: longitude,
      speedMetersPerSecond: speedMetersPerSecond,
      speedAccuracy: 1,
      horizontalAccuracy: 5,
      heading: 90,
      headingAccuracy: 30,
      timestamp: timestamp,
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

class _FakeHeading implements HeadingDataSource {
  _FakeHeading({this.available = true});

  final bool available;
  final _controller = StreamController<HeadingSensorSample>.broadcast();
  final locationUpdates = <TelemetrySample>[];

  void emit(HeadingSensorSample sample) => _controller.add(sample);

  @override
  Stream<HeadingSensorSample> get samples => _controller.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> updateLocation(TelemetrySample sample) async {
    locationUpdates.add(sample);
  }
}

class _FakeRoadLimit implements RoadLimitDataSource {
  _FakeRoadLimit({this.limit, this.name});
  final int? limit;
  final String? name;
  int calls = 0;
  @override
  Future<List<RoadSegment>> fetchCandidates(
      {required double latitude, required double longitude}) async {
    calls++;
    if (limit == null && name == null) return const [];
    final tags = <String, String>{};
    if (limit != null) tags['maxspeed'] = '$limit';
    tags['name'] = name ?? 'Via de teste';
    return [
      RoadSegment(
        id: 1,
        points: const [GeoPoint(-23.5, -46.6002), GeoPoint(-23.5, -46.5998)],
        tags: tags,
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
