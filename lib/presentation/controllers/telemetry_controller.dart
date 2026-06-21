import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/audio/flutter_tts_speech_engine.dart';
import '../../data/location/geolocator_location_data_source.dart';
import '../../data/road_limit/overpass_road_limit_provider.dart';
import '../../domain/entities/voice_alert.dart';
import '../../domain/services/audio_announcement_coordinator.dart';
import '../../domain/services/speed_alert_engine.dart';
import '../../domain/telemetry/road_matcher.dart';
import '../../domain/telemetry/telemetry_dependencies.dart';

enum TrackingStatus {
  stopped,
  awaitingGps,
  active,
  permissionDenied,
  permissionDeniedForever,
  locationDisabled,
}

enum TelemetryDegradedReason {
  gpsWeak,
  locationStale,
  roadMatchLowConfidence,
  overpassUnavailable,
  onlineDataDisabled,
  audioUnavailable,
  ttsUnavailable,
  countryBoundaryUncertain,
}

class TelemetryController extends ChangeNotifier {
  TelemetryController({
    LocationDataSource? location,
    RoadLimitDataSource? roadLimit,
    SpeechEngine? speech,
    DateTime Function()? clock,
  })  : _location = location ?? GeolocatorLocationDataSource(),
        _roadLimit = roadLimit ?? OverpassRoadLimitProvider(),
        _speech = speech ?? FlutterTtsSpeechEngine(),
        _clock = clock ?? DateTime.now;

  final LocationDataSource _location;
  final RoadLimitDataSource _roadLimit;
  final SpeechEngine _speech;
  final DateTime Function() _clock;
  final _alerts = SpeedAlertEngine();
  final _audio = AudioAnnouncementCoordinator();
  final _matcher = RoadMatcher();
  final Set<TelemetryDegradedReason> degradationReasons = {};
  StreamSubscription<TelemetrySample>? _subscription;
  Timer? _staleTimer;
  TelemetrySample? _lastValidSample;
  TelemetrySample? _lastRoadLookup;
  RoadMatch? _pendingRoad;
  List<RoadSegment> _cachedCandidates = const [];
  DateTime? _pendingRoadSince;
  DateTime? _lastRoadLookupAt;
  DateTime? _lastLimitAnnouncement;
  double? _filteredSpeed;
  int _session = 0;
  bool _allowOnline = false;
  bool _announceLimits = true;
  bool _announceBands = false;
  DateTime? _suppressRelativeAlertsUntil;
  final Set<int> _ignoredWayIds = {};

  TrackingStatus status = TrackingStatus.stopped;
  double? speedKmh;
  double? filteredNeedleSpeed;
  int? roadSpeedLimit;
  int? roadWayId;
  int? lastConfirmedWayId;
  String? roadName;
  String? errorMessage;

  bool get isTracking =>
      status == TrackingStatus.awaitingGps || status == TrackingStatus.active;
  bool get hasFreshLocation =>
      _lastValidSample != null &&
      _clock().difference(_sampleTime(_lastValidSample!)) <=
          const Duration(seconds: 3);

  DateTime _sampleTime(TelemetrySample sample) => sample.timestamp ?? _clock();

  Future<void> start({
    required bool allowOnline,
    required bool announceLimits,
    required bool announceBands,
    double volume = 1,
    double speechRate = 1,
  }) async {
    await stop();
    _session++;
    _allowOnline = allowOnline;
    _announceLimits = announceLimits;
    _announceBands = announceBands;
    degradationReasons.clear();
    if (!allowOnline) degradationReasons.add(TelemetryDegradedReason.onlineDataDisabled);
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
      status = permission == LocationPermissionStatus.deniedForever
          ? TrackingStatus.permissionDeniedForever
          : TrackingStatus.permissionDenied;
      notifyListeners();
      return;
    }
    status = TrackingStatus.awaitingGps;
    final ttsAvailable = await _speech.configure(volume: volume, speechRate: speechRate);
    if (!ttsAvailable) degradationReasons.add(TelemetryDegradedReason.ttsUnavailable);
    final session = _session;
    _subscription = _location.samples.listen(
      (sample) {
        if (session == _session) _onSample(sample);
      },
      onError: (_) {
        errorMessage = 'Não foi possível receber a localização.';
        degradationReasons.add(TelemetryDegradedReason.gpsWeak);
        notifyListeners();
      },
    );
    _staleTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateStaleState());
    notifyListeners();
  }

  void _onSample(TelemetrySample sample) {
    if (!_isValid(sample)) {
      degradationReasons.add(TelemetryDegradedReason.gpsWeak);
      notifyListeners();
      return;
    }
    _lastValidSample = sample;
    degradationReasons.remove(TelemetryDegradedReason.locationStale);
    if (sample.horizontalAccuracy <= 15 && sample.speedAccuracy <= 1.5) {
      degradationReasons.remove(TelemetryDegradedReason.gpsWeak);
    } else {
      degradationReasons.add(TelemetryDegradedReason.gpsWeak);
    }
    speedKmh = math.max(0, sample.speedMetersPerSecond * 3.6);
    _filteredSpeed = _filteredSpeed == null
        ? speedKmh
        : .35 * speedKmh! + .65 * _filteredSpeed!;
    filteredNeedleSpeed = _filteredSpeed;
    status = TrackingStatus.active;
    _maybeUpdateRoadLimit(sample);
    _maybeAnnounce(sample);
    notifyListeners();
  }

  bool _isValid(TelemetrySample sample) =>
      sample.latitude.isFinite &&
      sample.longitude.isFinite &&
      sample.speedMetersPerSecond.isFinite &&
      sample.horizontalAccuracy.isFinite &&
      sample.horizontalAccuracy <= 20 &&
      _clock().difference(_sampleTime(sample)) <= const Duration(seconds: 3);

  void _updateStaleState() {
    if (!isTracking) return;
    final last = _lastValidSample;
    if (last == null ||
        _clock().difference(_sampleTime(last)) > const Duration(seconds: 3)) {
      degradationReasons.add(TelemetryDegradedReason.locationStale);
    }
    if (last == null ||
        _clock().difference(_sampleTime(last)) > const Duration(seconds: 10)) {
      roadSpeedLimit = null;
      roadWayId = null;
      roadName = null;
    }
    notifyListeners();
  }

  Future<void> _maybeAnnounce(TelemetrySample sample) async {
    if (!hasFreshLocation || degradationReasons.contains(TelemetryDegradedReason.ttsUnavailable)) return;
    final alert = _alerts.process(
      speedKmh: speedKmh ?? 0,
      isValid: sample.speedAccuracy <= 1.5,
      roadSpeedLimit: roadSpeedLimit?.toDouble(),
    );
    if (alert == null || _ignoredWayIds.contains(roadWayId)) {
      return;
    }
    if (_suppressRelativeAlertsUntil?.isAfter(_clock()) == true &&
        alert.kind != VoiceAlertKind.speedBand) {
      return;
    }
    final shouldSpeak = switch (alert.kind) {
      VoiceAlertKind.speedBand => _announceBands,
      VoiceAlertKind.belowHalfLimit || VoiceAlertKind.aboveLimit || VoiceAlertKind.roadLimitChanged => _announceLimits,
    };
    if (!shouldSpeak) return;
    try {
      await _audio.announce(alert, _speech);
    } catch (_) {
      degradationReasons.add(TelemetryDegradedReason.audioUnavailable);
      notifyListeners();
    }
  }

  Future<void> _maybeUpdateRoadLimit(TelemetrySample sample) async {
    if (!_allowOnline || !hasFreshLocation) return;
    if (!_isPlausiblyBrazilian(sample)) {
      roadSpeedLimit = null;
      degradationReasons.add(TelemetryDegradedReason.countryBoundaryUncertain);
      notifyListeners();
      return;
    }
    if (sample.horizontalAccuracy > 15 || sample.speedAccuracy > 1.5 ||
        sample.heading == null || (sample.headingAccuracy ?? 999) > 20) {
      degradationReasons.add(TelemetryDegradedReason.gpsWeak);
      return;
    }
    if (!_shouldLookupRoad(sample)) {
      _confirmRoad(sample, _cachedCandidates);
      return;
    }
    _lastRoadLookup = sample;
    _lastRoadLookupAt = _clock();
    final session = _session;
    try {
      final candidates = await _roadLimit.fetchCandidates(latitude: sample.latitude, longitude: sample.longitude);
      if (session != _session || !_allowOnline || !hasFreshLocation) return;
      _cachedCandidates = candidates;
      await _confirmRoad(sample, candidates);
    } catch (_) {
      if (session == _session) {
        degradationReasons.add(TelemetryDegradedReason.overpassUnavailable);
        notifyListeners();
      }
    }
  }

  Future<void> _confirmRoad(TelemetrySample sample, List<RoadSegment> candidates) async {
    final match = _matcher.select(sample: sample, candidates: candidates, previousWayId: roadWayId);
    if (match == null) {
      degradationReasons.add(TelemetryDegradedReason.roadMatchLowConfidence);
      return;
    }
    if (_pendingRoad?.wayId != match.wayId) {
      _pendingRoad = match;
      _pendingRoadSince = _sampleTime(sample);
      return;
    }
    if (_sampleTime(sample).difference(_pendingRoadSince!).inSeconds < 1) return;
    _pendingRoad = null;
    _pendingRoadSince = null;
    final changed = roadWayId != match.wayId || roadSpeedLimit != match.limit;
    roadWayId = match.wayId;
    lastConfirmedWayId = match.wayId;
    roadSpeedLimit = match.limit;
    roadName = match.name;
    degradationReasons
      ..remove(TelemetryDegradedReason.roadMatchLowConfidence)
      ..remove(TelemetryDegradedReason.overpassUnavailable);
    if (changed) await _announceRoadLimit(match);
    notifyListeners();
  }

  Future<void> _announceRoadLimit(RoadMatch match) async {
    final last = _lastLimitAnnouncement;
    if (!_announceLimits || degradationReasons.contains(TelemetryDegradedReason.ttsUnavailable) ||
        (last != null && _clock().difference(last) < const Duration(seconds: 30))) {
      return;
    }
    _lastLimitAnnouncement = _clock();
    _suppressRelativeAlertsUntil = _clock().add(const Duration(seconds: 10));
    try {
      await _audio.announce(
        VoiceAlert(kind: VoiceAlertKind.roadLimitChanged, message: 'Atenção: Novo limite de velocidade: ${match.limit} quilômetros por hora.'),
        _speech,
      );
    } catch (_) {
      degradationReasons.add(TelemetryDegradedReason.audioUnavailable);
    }
  }

  bool _shouldLookupRoad(TelemetrySample sample) {
    final last = _lastRoadLookup;
    final lastAt = _lastRoadLookupAt;
    if (last == null || lastAt == null) return true;
    if (_clock().difference(lastAt) < const Duration(seconds: 10)) return false;
    if (_clock().difference(lastAt) >= const Duration(seconds: 60)) return true;
    return _approximateDistanceMeters(last, sample) >= 50;
  }

  double _approximateDistanceMeters(TelemetrySample one, TelemetrySample two) {
    const metersPerDegree = 111000.0;
    final latitude = (one.latitude - two.latitude) * metersPerDegree;
    final longitude = (one.longitude - two.longitude) * metersPerDegree * math.cos(one.latitude * math.pi / 180);
    return math.sqrt(latitude * latitude + longitude * longitude);
  }

  bool _isPlausiblyBrazilian(TelemetrySample sample) {
    // Restrição conservadora do protótipo: bloqueia consultas fora da extensão
    // territorial brasileira e perto das suas bordas aproximadas.
    const minLatitude = -33.8, maxLatitude = 5.4, minLongitude = -74.1, maxLongitude = -34.7;
    const margin = .005; // aproximadamente 500 m
    final inside = sample.latitude > minLatitude && sample.latitude < maxLatitude &&
        sample.longitude > minLongitude && sample.longitude < maxLongitude;
    final nearEdge = (sample.latitude - minLatitude).abs() < margin ||
        (sample.latitude - maxLatitude).abs() < margin ||
        (sample.longitude - minLongitude).abs() < margin ||
        (sample.longitude - maxLongitude).abs() < margin;
    if (nearEdge) degradationReasons.add(TelemetryDegradedReason.countryBoundaryUncertain);
    return inside && !nearEdge;
  }

  void ignoreCurrentRoadForSession() {
    final wayId = roadWayId;
    if (wayId != null) _ignoredWayIds.add(wayId);
  }

  Future<void> stop() async {
    _session++;
    await _subscription?.cancel();
    _subscription = null;
    _staleTimer?.cancel();
    _staleTimer = null;
    await _audio.stop(_speech);
    status = TrackingStatus.stopped;
    speedKmh = null;
    filteredNeedleSpeed = null;
    roadSpeedLimit = null;
    roadWayId = null;
    roadName = null;
    _filteredSpeed = null;
    _lastValidSample = null;
    _lastRoadLookup = null;
    _ignoredWayIds.clear();
    notifyListeners();
  }

  Future<void> openAppSettings() => _location.openAppSettings();
  Future<void> openLocationSettings() => _location.openLocationSettings();

  @override
  void dispose() {
    _subscription?.cancel();
    _staleTimer?.cancel();
    _roadLimit.dispose();
    _speech.stop();
    super.dispose();
  }
}
