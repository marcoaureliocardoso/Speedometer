import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/audio/flutter_tts_speech_engine.dart';
import '../../data/location/geolocator_location_data_source.dart';
import '../../data/road_limit/overpass_road_limit_provider.dart';
import '../../domain/entities/voice_alert.dart';
import '../../domain/services/audio_announcement_coordinator.dart';
import '../../domain/services/course_heading_estimator.dart';
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
  positionWeak,
  speedWeak,
  locationStale,
  roadMatchLowConfidence,
  overpassUnavailable,
  onlineDataDisabled,
  audioUnavailable,
  ttsUnavailable,
  headingWeak,
  countryBoundaryUncertain,
}

class TelemetryController extends ChangeNotifier {
  TelemetryController({
    LocationDataSource? location,
    RoadLimitDataSource? roadLimit,
    SpeechEngine? speech,
    HeadingDataSource? heading,
    DateTime Function()? clock,
    this.staleAfter = const Duration(seconds: 3),
    this.limitExpiryAfter = const Duration(seconds: 10),
    this.staleCheckInterval = const Duration(seconds: 1),
  })  : _location = location ?? GeolocatorLocationDataSource(),
        _roadLimit = roadLimit ?? OverpassRoadLimitProvider(),
        _speech = speech ?? FlutterTtsSpeechEngine(),
        _heading = heading,
        _clock = clock ?? DateTime.now;

  final LocationDataSource _location;
  final RoadLimitDataSource _roadLimit;
  final SpeechEngine _speech;
  final HeadingDataSource? _heading;
  final DateTime Function() _clock;
  final Duration staleAfter;
  final Duration limitExpiryAfter;
  final Duration staleCheckInterval;
  final _alerts = SpeedAlertEngine();
  final _audio = AudioAnnouncementCoordinator();
  final _courseHeading = CourseHeadingEstimator();
  final _matcher = RoadMatcher();
  final Set<TelemetryDegradedReason> degradationReasons = {};
  StreamSubscription<TelemetrySample>? _subscription;
  StreamSubscription<HeadingSensorSample>? _headingSubscription;
  Timer? _staleTimer;
  TelemetrySample? _lastValidSample;
  TelemetrySample? _lastRoadLookup;
  RoadMatch? _pendingRoad;
  List<RoadSegment> _cachedCandidates = const [];
  DateTime? _pendingRoadSince;
  DateTime? _lastRoadLookupAt;
  RoadMatch? _pendingRoadLimitAnnouncement;
  double? _filteredSpeed;
  int _session = 0;
  bool _allowOnline = false;
  bool _announceLimits = true;
  bool _announceBands = false;
  int _bandIntervalKmh = 5;
  int? _customSpeedLimitKmh;
  bool _ttsReady = false;
  DateTime? _suppressRelativeAlertsUntil;
  _RecentSensorHeading? _recentSensorHeading;
  final Set<int> _ignoredWayIds = {};

  TrackingStatus status = TrackingStatus.stopped;
  double? speedKmh;
  double? filteredNeedleSpeed;
  int? roadSpeedLimit;
  int? roadWayId;
  int? lastConfirmedWayId;
  String? roadName;
  String? errorMessage;
  DateTime? lastLocationReceivedAt;
  Duration? lastLocationLatency;

  bool get isTracking =>
      status == TrackingStatus.awaitingGps || status == TrackingStatus.active;
  bool get hasFreshLocation =>
      _lastValidSample != null &&
      _clock().difference(_sampleTime(_lastValidSample!)) <= staleAfter;

  DateTime _sampleTime(TelemetrySample sample) => sample.timestamp ?? _clock();

  Future<void> start({
    required bool allowOnline,
    required bool announceLimits,
    required bool announceBands,
    int bandIntervalKmh = 5,
    int? customSpeedLimitKmh,
    double volume = 1,
    double speechRate = 1,
  }) async {
    await stop();
    _alerts.reset();
    _session++;
    _allowOnline = allowOnline;
    _announceLimits = announceLimits;
    _announceBands = announceBands;
    _bandIntervalKmh = bandIntervalKmh == 10 ? 10 : 5;
    _customSpeedLimitKmh =
        customSpeedLimitKmh != null && customSpeedLimitKmh > 0
            ? customSpeedLimitKmh
            : null;
    _ttsReady = false;
    degradationReasons.clear();
    if (!allowOnline) {
      degradationReasons.add(TelemetryDegradedReason.onlineDataDisabled);
    }
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
    final session = _session;
    _subscription = _location.samples.listen(
      (sample) {
        if (session == _session) _onSample(sample);
      },
      onError: (_) {
        errorMessage = 'Não foi possível receber a localização.';
        degradationReasons.add(TelemetryDegradedReason.positionWeak);
        notifyListeners();
      },
    );
    final headingDataSource = _heading;
    if (allowOnline && headingDataSource != null) {
      try {
        if (await headingDataSource.isAvailable()) {
          _headingSubscription = headingDataSource.samples.listen(
            (heading) {
              if (session == _session) {
                _recentSensorHeading = _RecentSensorHeading(heading, _clock());
              }
            },
            onError: (_) {},
          );
        }
      } catch (_) {
        // O rumo GPS e o rumo por deslocamento continuam disponíveis.
      }
    }
    _staleTimer =
        Timer.periodic(staleCheckInterval, (_) => _updateStaleState());
    notifyListeners();

    final ttsAvailable =
        await _speech.configure(volume: volume, speechRate: speechRate);
    if (session != _session) {
      return;
    }
    _ttsReady = ttsAvailable;
    if (!ttsAvailable) {
      degradationReasons.add(TelemetryDegradedReason.ttsUnavailable);
    }
    final pendingRoadLimit = _pendingRoadLimitAnnouncement;
    if (ttsAvailable && pendingRoadLimit != null) {
      _pendingRoadLimitAnnouncement = null;
      unawaited(_announceRoadLimit(pendingRoadLimit));
    }
    notifyListeners();
  }

  void _onSample(TelemetrySample sample) {
    _recordLocationLatency(sample);
    if (!_isValid(sample)) {
      degradationReasons.add(TelemetryDegradedReason.positionWeak);
      notifyListeners();
      return;
    }
    _lastValidSample = sample;
    if (_allowOnline) unawaited(_updateHeadingLocation(sample));
    degradationReasons.remove(TelemetryDegradedReason.locationStale);
    if (sample.horizontalAccuracy <= 15) {
      degradationReasons.remove(TelemetryDegradedReason.positionWeak);
    } else {
      degradationReasons.add(TelemetryDegradedReason.positionWeak);
    }
    if (sample.speedAccuracy <= 1.5) {
      degradationReasons.remove(TelemetryDegradedReason.speedWeak);
    } else {
      degradationReasons.add(TelemetryDegradedReason.speedWeak);
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

  Future<void> _updateHeadingLocation(TelemetrySample sample) async {
    try {
      await _heading?.updateLocation(sample);
    } catch (_) {
      // O rumo GPS e o rumo por deslocamento continuam disponíveis.
    }
  }

  void _recordLocationLatency(TelemetrySample sample) {
    final receivedAt = _clock();
    lastLocationReceivedAt = receivedAt;
    final timestamp = sample.timestamp;
    if (timestamp == null) {
      lastLocationLatency = null;
      return;
    }
    final latency = receivedAt.difference(timestamp);
    lastLocationLatency = latency.isNegative ? Duration.zero : latency;
  }

  bool _isValid(TelemetrySample sample) =>
      sample.latitude.isFinite &&
      sample.longitude.isFinite &&
      sample.speedMetersPerSecond.isFinite &&
      sample.horizontalAccuracy.isFinite &&
      sample.horizontalAccuracy <= 20 &&
      _clock().difference(_sampleTime(sample)) <= staleAfter;

  void _updateStaleState() {
    if (!isTracking) return;
    final last = _lastValidSample;
    if (last == null || _clock().difference(_sampleTime(last)) > staleAfter) {
      degradationReasons.add(TelemetryDegradedReason.locationStale);
    }
    if (last == null ||
        _clock().difference(_sampleTime(last)) > limitExpiryAfter) {
      roadSpeedLimit = null;
      roadWayId = null;
      roadName = null;
    }
    notifyListeners();
  }

  Future<void> _maybeAnnounce(TelemetrySample sample) async {
    if (!_ttsReady ||
        !hasFreshLocation ||
        degradationReasons.contains(TelemetryDegradedReason.ttsUnavailable)) {
      return;
    }
    final alert = _alerts.process(
      speedKmh: speedKmh ?? 0,
      isValid: sample.speedAccuracy <= 1.5,
      roadSpeedLimit: roadSpeedLimit?.toDouble(),
      customSpeedLimitKmh: _customSpeedLimitKmh,
      bandIntervalKmh: _bandIntervalKmh,
    );
    if (alert == null ||
        (alert.kind != VoiceAlertKind.customSpeedLimitExceeded &&
            _ignoredWayIds.contains(roadWayId))) {
      return;
    }
    if (_suppressRelativeAlertsUntil?.isAfter(_clock()) == true &&
        (alert.kind == VoiceAlertKind.belowHalfLimit ||
            alert.kind == VoiceAlertKind.aboveLimit)) {
      return;
    }
    final shouldSpeak = switch (alert.kind) {
      VoiceAlertKind.speedBand => _announceBands,
      VoiceAlertKind.belowHalfLimit ||
      VoiceAlertKind.aboveLimit ||
      VoiceAlertKind.customSpeedLimitExceeded ||
      VoiceAlertKind.roadLimitChanged =>
        _announceLimits,
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
    if (sample.horizontalAccuracy > 15) {
      degradationReasons.add(TelemetryDegradedReason.positionWeak);
      return;
    }
    final roadSample = _withBestHeading(sample);
    if (!_shouldLookupRoad(sample)) {
      _confirmRoad(roadSample, _cachedCandidates);
      return;
    }
    _lastRoadLookup = sample;
    _lastRoadLookupAt = _clock();
    final session = _session;
    try {
      final candidates = await _roadLimit.fetchCandidates(
          latitude: sample.latitude, longitude: sample.longitude);
      if (session != _session || !_allowOnline || !hasFreshLocation) return;
      _cachedCandidates = candidates;
      await _confirmRoad(roadSample, candidates);
    } catch (_) {
      if (session == _session) {
        degradationReasons.add(TelemetryDegradedReason.overpassUnavailable);
        notifyListeners();
      }
    }
  }

  TelemetrySample _withBestHeading(TelemetrySample sample) {
    final estimated = _courseHeading.estimate(sample, _sampleTime(sample));
    var heading = sample.heading;
    var accuracy = sample.headingAccuracy ?? double.infinity;
    if (estimated != null && estimated.accuracyDegrees < accuracy) {
      heading = estimated.degrees;
      accuracy = estimated.accuracyDegrees;
    }
    final sensorHeading = _recentSensorHeading;
    final sensorIsFresh = sensorHeading != null &&
        _clock().difference(sensorHeading.receivedAt) <=
            const Duration(seconds: 1);
    final isLowSpeed = sample.speedMetersPerSecond * 3.6 <= 10;
    if (accuracy > 20 &&
        isLowSpeed &&
        sensorIsFresh &&
        sensorHeading.sample.accuracy >= 3) {
      // O Android só informa níveis de calibração, não graus de incerteza.
      // "Alta" é mapeada para 15 graus, ainda abaixo do limite do matcher.
      heading = sensorHeading.sample.degrees;
      accuracy = 15;
    }
    if (heading == sample.heading && accuracy == sample.headingAccuracy) {
      return sample;
    }
    return TelemetrySample(
      latitude: sample.latitude,
      longitude: sample.longitude,
      speedMetersPerSecond: sample.speedMetersPerSecond,
      speedAccuracy: sample.speedAccuracy,
      horizontalAccuracy: sample.horizontalAccuracy,
      heading: heading,
      headingAccuracy: accuracy.isFinite ? accuracy : null,
      timestamp: sample.timestamp,
    );
  }

  Future<void> _confirmRoad(
      TelemetrySample sample, List<RoadSegment> candidates) async {
    final match = _matcher.select(
        sample: sample, candidates: candidates, previousWayId: roadWayId);
    if (match == null) {
      _pendingRoad = null;
      _pendingRoadSince = null;
      final headingIsReliable =
          sample.heading != null && (sample.headingAccuracy ?? 999) <= 20;
      if (headingIsReliable) {
        degradationReasons
          ..add(TelemetryDegradedReason.roadMatchLowConfidence)
          ..remove(TelemetryDegradedReason.headingWeak);
      } else {
        degradationReasons
          ..add(TelemetryDegradedReason.headingWeak)
          ..remove(TelemetryDegradedReason.roadMatchLowConfidence);
      }
      return;
    }
    if (_pendingRoad?.wayId != match.wayId) {
      _pendingRoad = match;
      _pendingRoadSince = _sampleTime(sample);
      return;
    }
    if (_sampleTime(sample).difference(_pendingRoadSince!).inSeconds < 1) {
      return;
    }
    _pendingRoad = null;
    _pendingRoadSince = null;
    final roadOrLimitChanged =
        roadWayId != match.wayId || roadSpeedLimit != match.limit;
    roadWayId = match.wayId;
    lastConfirmedWayId = match.wayId;
    roadSpeedLimit = match.limit;
    roadName = match.name;
    degradationReasons
      ..remove(TelemetryDegradedReason.roadMatchLowConfidence)
      ..remove(TelemetryDegradedReason.headingWeak)
      ..remove(TelemetryDegradedReason.overpassUnavailable);
    if (roadOrLimitChanged && match.limit != null) {
      await _announceRoadLimit(match);
    }
    notifyListeners();
  }

  Future<void> _announceRoadLimit(RoadMatch match) async {
    final limit = match.limit;
    if (limit == null) return;
    if (!_announceLimits ||
        degradationReasons.contains(TelemetryDegradedReason.ttsUnavailable)) {
      return;
    }
    if (!_ttsReady) {
      _pendingRoadLimitAnnouncement = match;
      return;
    }
    _suppressRelativeAlertsUntil = _clock().add(const Duration(seconds: 10));
    try {
      await _audio.announce(
        VoiceAlert(
            kind: VoiceAlertKind.roadLimitChanged,
            message:
                'Atenção: Novo limite de velocidade: $limit quilômetros por hora.'),
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
    final longitude = (one.longitude - two.longitude) *
        metersPerDegree *
        math.cos(one.latitude * math.pi / 180);
    return math.sqrt(latitude * latitude + longitude * longitude);
  }

  bool _isPlausiblyBrazilian(TelemetrySample sample) {
    // Restrição conservadora do protótipo: bloqueia consultas fora da extensão
    // territorial brasileira e perto das suas bordas aproximadas.
    const minLatitude = -33.8,
        maxLatitude = 5.4,
        minLongitude = -74.1,
        maxLongitude = -34.7;
    const margin = .005; // aproximadamente 500 m
    final inside = sample.latitude > minLatitude &&
        sample.latitude < maxLatitude &&
        sample.longitude > minLongitude &&
        sample.longitude < maxLongitude;
    final nearEdge = (sample.latitude - minLatitude).abs() < margin ||
        (sample.latitude - maxLatitude).abs() < margin ||
        (sample.longitude - minLongitude).abs() < margin ||
        (sample.longitude - maxLongitude).abs() < margin;
    if (nearEdge) {
      degradationReasons.add(TelemetryDegradedReason.countryBoundaryUncertain);
    }
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
    await _headingSubscription?.cancel();
    _headingSubscription = null;
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
    _ttsReady = false;
    _lastValidSample = null;
    _lastRoadLookup = null;
    _pendingRoadLimitAnnouncement = null;
    _courseHeading.reset();
    _recentSensorHeading = null;
    lastLocationReceivedAt = null;
    lastLocationLatency = null;
    _ignoredWayIds.clear();
    notifyListeners();
  }

  Future<void> openAppSettings() => _location.openAppSettings();
  Future<void> openLocationSettings() => _location.openLocationSettings();

  @override
  void dispose() {
    _subscription?.cancel();
    _headingSubscription?.cancel();
    _staleTimer?.cancel();
    _roadLimit.dispose();
    _speech.stop();
    super.dispose();
  }
}

class _RecentSensorHeading {
  const _RecentSensorHeading(this.sample, this.receivedAt);

  final HeadingSensorSample sample;
  final DateTime receivedAt;
}
