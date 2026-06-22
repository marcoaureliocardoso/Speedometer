import '../entities/voice_alert.dart';

/// Produz alertas confirmados por duas leituras válidas consecutivas.
/// A camada de apresentação decide se TTS está habilitado para o modo de voz.
class SpeedAlertEngine {
  double? _lastSpeed;
  _PendingAlert? _pending;
  bool _belowHalfArmed = true;
  bool _aboveLimitArmed = true;
  bool _customSpeedLimitArmed = true;
  int _belowHalfRearmReadings = 0;
  int _aboveLimitRearmReadings = 0;
  int _customSpeedLimitRearmReadings = 0;
  final Map<int, bool> _ascendingBandArmed = {};
  final Map<int, bool> _descendingBandArmed = {};

  void reset() {
    _lastSpeed = null;
    _pending = null;
    _belowHalfArmed = true;
    _aboveLimitArmed = true;
    _customSpeedLimitArmed = true;
    _belowHalfRearmReadings = 0;
    _aboveLimitRearmReadings = 0;
    _customSpeedLimitRearmReadings = 0;
    _ascendingBandArmed.clear();
    _descendingBandArmed.clear();
  }

  VoiceAlert? process({
    required double speedKmh,
    required bool isValid,
    required double? roadSpeedLimit,
    int? customSpeedLimitKmh,
    int bandIntervalKmh = 5,
  }) {
    if (!isValid || speedKmh.isNegative) return null;

    final customSpeedLimit =
        customSpeedLimitKmh != null && customSpeedLimitKmh > 0
            ? customSpeedLimitKmh.toDouble()
            : null;
    _rearmRelativeAlerts(speedKmh, roadSpeedLimit, customSpeedLimit);
    final candidate = _candidate(
      speedKmh,
      roadSpeedLimit,
      customSpeedLimit,
      bandIntervalKmh == 10 ? 10 : 5,
    );
    final pending = _pending;
    if (pending != null) {
      if (pending.matches(speedKmh, roadSpeedLimit, customSpeedLimit)) {
        _pending = null;
        _lastSpeed = speedKmh;
        _consume(pending);
        return pending.alert;
      }
      _pending = null;
    }

    _lastSpeed = speedKmh;
    if (candidate != null) _pending = candidate;
    return null;
  }

  _PendingAlert? _candidate(
      double speed, double? limit, double? customLimit, int bandIntervalKmh) {
    final previous = _lastSpeed;
    if (customLimit != null &&
        speed > customLimit &&
        _customSpeedLimitArmed &&
        (previous == null || previous <= customLimit)) {
      return _PendingAlert.customSpeedLimit(customLimit);
    }
    if (limit != null && limit > 0) {
      if (speed < limit / 2 &&
          _belowHalfArmed &&
          (previous == null || previous >= limit / 2)) {
        return _PendingAlert.belowHalf(limit);
      }
      if (speed > limit &&
          _aboveLimitArmed &&
          (previous == null || previous <= limit)) {
        return _PendingAlert.aboveLimit(limit);
      }
    }
    if (previous == null) return null;

    final from = previous.floor();
    final to = speed.floor();
    if (to > from) {
      final band = (to ~/ bandIntervalKmh) * bandIntervalKmh;
      if (band > 0 && band > from && _ascendingBandArmed[band] != false) {
        return _PendingAlert.band(band, ascending: true);
      }
    }
    if (to < from) {
      final band =
          ((to + bandIntervalKmh - 1) ~/ bandIntervalKmh) * bandIntervalKmh;
      if (band > 0 && band < from && _descendingBandArmed[band] != false) {
        return _PendingAlert.band(band, ascending: false);
      }
    }
    return null;
  }

  void _consume(_PendingAlert pending) {
    switch (pending.alert.kind) {
      case VoiceAlertKind.roadLimitChanged:
        return;
      case VoiceAlertKind.belowHalfLimit:
        _belowHalfArmed = false;
        return;
      case VoiceAlertKind.aboveLimit:
        _aboveLimitArmed = false;
        return;
      case VoiceAlertKind.customSpeedLimitExceeded:
        _customSpeedLimitArmed = false;
        return;
      case VoiceAlertKind.speedBand:
        final band = pending.band!;
        (pending.ascending == true
            ? _ascendingBandArmed
            : _descendingBandArmed)[band] = false;
        return;
    }
  }

  void _rearmRelativeAlerts(double speed, double? limit, double? customLimit) {
    if (limit != null && limit > 0) {
      _belowHalfRearmReadings =
          speed >= limit / 2 + 2 ? _belowHalfRearmReadings + 1 : 0;
      _aboveLimitRearmReadings =
          speed <= limit - 2 ? _aboveLimitRearmReadings + 1 : 0;
      if (_belowHalfRearmReadings >= 2) _belowHalfArmed = true;
      if (_aboveLimitRearmReadings >= 2) _aboveLimitArmed = true;
    }
    if (customLimit != null) {
      _customSpeedLimitRearmReadings =
          speed <= customLimit - 2 ? _customSpeedLimitRearmReadings + 1 : 0;
      if (_customSpeedLimitRearmReadings >= 2) _customSpeedLimitArmed = true;
    }
  }
}

class _PendingAlert {
  const _PendingAlert._({
    required this.alert,
    required this.condition,
    this.band,
    this.ascending,
  });

  factory _PendingAlert.belowHalf(double limit) => _PendingAlert._(
        alert: const VoiceAlert(
          kind: VoiceAlertKind.belowHalfLimit,
          message: 'Velocidade abaixo da metade do limite da via.',
        ),
        condition: (speed, currentLimit, _) =>
            currentLimit == limit && speed < limit / 2,
      );

  factory _PendingAlert.aboveLimit(double limit) => _PendingAlert._(
        alert: const VoiceAlert(
          kind: VoiceAlertKind.aboveLimit,
          message: 'Atenção: acima do limite de velocidade.',
        ),
        condition: (speed, currentLimit, _) =>
            currentLimit == limit && speed > limit,
      );

  factory _PendingAlert.customSpeedLimit(double limit) => _PendingAlert._(
        alert: VoiceAlert(
          kind: VoiceAlertKind.customSpeedLimitExceeded,
          message:
              'Limite de velocidade ${limit.toStringAsFixed(0)}Km/h ultrapassado.',
        ),
        condition: (speed, _, currentCustomLimit) =>
            currentCustomLimit == limit && speed > limit,
      );

  factory _PendingAlert.band(int band, {required bool ascending}) =>
      _PendingAlert._(
        alert: VoiceAlert(
          kind: VoiceAlertKind.speedBand,
          message: '$band quilômetros por hora.',
        ),
        condition: (speed, _, __) => ascending ? speed >= band : speed <= band,
        band: band,
        ascending: ascending,
      );

  final VoiceAlert alert;
  final bool Function(double speed, double? limit, double? customLimit)
      condition;
  final int? band;
  final bool? ascending;

  bool matches(double speed, double? limit, double? customLimit) =>
      condition(speed, limit, customLimit);
}
