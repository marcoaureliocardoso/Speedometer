import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/audio/flutter_tts_speech_engine.dart';
import '../../data/location/geolocator_location_data_source.dart';
import '../../data/road_limit/overpass_road_limit_provider.dart';
import '../../domain/entities/voice_alert.dart';
import '../../domain/services/speed_alert_engine.dart';
import '../../domain/telemetry/telemetry_dependencies.dart';

enum TrackingStatus {
  stopped,
  awaitingGps,
  active,
  permissionDenied,
  locationDisabled
}

class TelemetryController extends ChangeNotifier {
  TelemetryController({
    LocationDataSource? location,
    RoadLimitDataSource? roadLimit,
    SpeechEngine? speech,
  })  : _location = location ?? GeolocatorLocationDataSource(),
        _roadLimit = roadLimit ?? OverpassRoadLimitProvider(),
        _speech = speech ?? FlutterTtsSpeechEngine();

  final LocationDataSource _location;
  final RoadLimitDataSource _roadLimit;
  final SpeechEngine _speech;
  final _alerts = SpeedAlertEngine();
  StreamSubscription<TelemetrySample>? _subscription;
  TelemetrySample? _lastRoadLookup;
  bool _allowOnline = false;
  bool _announceLimits = true;
  bool _announceBands = false;

  TrackingStatus status = TrackingStatus.stopped;
  double? speedKmh;
  int? roadSpeedLimit;
  String? errorMessage;

  bool get isTracking =>
      status == TrackingStatus.awaitingGps || status == TrackingStatus.active;

  Future<void> start({
    required bool allowOnline,
    required bool announceLimits,
    required bool announceBands,
  }) async {
    _allowOnline = allowOnline;
    _announceLimits = announceLimits;
    _announceBands = announceBands;
    errorMessage = null;
    if (!await _location.isServiceEnabled()) {
      status = TrackingStatus.locationDisabled;
      notifyListeners();
      return;
    }
    var permission = await _location.checkPermission();
    if (permission == LocationPermissionStatus.denied) {
      permission = await _location.requestPermission();
    }
    if (permission != LocationPermissionStatus.granted) {
      status = TrackingStatus.permissionDenied;
      notifyListeners();
      return;
    }
    status = TrackingStatus.awaitingGps;
    notifyListeners();
    await _speech.configure();
    _subscription = _location.samples.listen(_onSample, onError: (_) {
      errorMessage = 'Não foi possível receber a localização.';
      notifyListeners();
    });
  }

  void _onSample(TelemetrySample sample) {
    speedKmh = sample.speedMetersPerSecond.isNegative
        ? 0
        : sample.speedMetersPerSecond * 3.6;
    status = TrackingStatus.active;
    notifyListeners();
    _maybeUpdateRoadLimit(sample);
    _maybeAnnounce(sample);
  }

  Future<void> _maybeAnnounce(TelemetrySample sample) async {
    final alert = _alerts.process(
      speedKmh: speedKmh ?? 0,
      isValid: sample.speedAccuracy <= 1.5,
      roadSpeedLimit: roadSpeedLimit?.toDouble(),
    );
    if (alert == null) return;
    final shouldSpeak = switch (alert.kind) {
      VoiceAlertKind.speedBand => _announceBands,
      VoiceAlertKind.belowHalfLimit ||
      VoiceAlertKind.aboveLimit =>
        _announceLimits,
    };
    if (shouldSpeak) await _speech.speak(alert.message);
  }

  Future<void> _maybeUpdateRoadLimit(TelemetrySample sample) async {
    if (!_allowOnline || !_shouldLookupRoad(sample)) return;
    _lastRoadLookup = sample;
    try {
      roadSpeedLimit = await _roadLimit.fetchLimit(
          latitude: sample.latitude, longitude: sample.longitude);
      notifyListeners();
    } catch (_) {
      // O painel mantém o limite indisponível após falha online.
    }
  }

  bool _shouldLookupRoad(TelemetrySample sample) {
    final last = _lastRoadLookup;
    if (last == null) return true;
    const metersPerDegree = 111000;
    final latitudeMeters =
        (sample.latitude - last.latitude).abs() * metersPerDegree;
    final longitudeMeters =
        (sample.longitude - last.longitude).abs() * metersPerDegree;
    return latitudeMeters + longitudeMeters >= 50;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _speech.stop();
    status = TrackingStatus.stopped;
    speedKmh = null;
    roadSpeedLimit = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _roadLimit.dispose();
    _speech.stop();
    super.dispose();
  }
}
