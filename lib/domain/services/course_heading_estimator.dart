import 'dart:math' as math;

import '../telemetry/telemetry_dependencies.dart';

class CourseHeadingEstimate {
  const CourseHeadingEstimate({
    required this.degrees,
    required this.accuracyDegrees,
  });

  final double degrees;
  final double accuracyDegrees;
}

/// Estima o rumo pelo deslocamento GPS entre duas posições confiáveis.
///
/// A estimativa só é exposta quando o deslocamento torna a incerteza angular
/// menor que 20 graus. Entre atualizações, o último rumo dura no máximo dois
/// segundos para permitir a confirmação de uma via em leituras consecutivas.
class CourseHeadingEstimator {
  static const _minimumDistanceMeters = 25.0;
  static const _maximumAccuracyDegrees = 20.0;
  static const _maximumAge = Duration(seconds: 2);

  TelemetrySample? _reference;
  _StoredEstimate? _lastEstimate;

  CourseHeadingEstimate? estimate(TelemetrySample sample, DateTime now) {
    final reference = _reference;
    if (reference == null) {
      _reference = sample;
      return null;
    }
    if (reference.horizontalAccuracy <= 0 || sample.horizontalAccuracy <= 0) {
      _reference = sample;
      _lastEstimate = null;
      return null;
    }

    final distance = _distanceMeters(reference, sample);
    if (distance >= _minimumDistanceMeters) {
      _reference = sample;
      final combinedPositionError = math.sqrt(
        reference.horizontalAccuracy * reference.horizontalAccuracy +
            sample.horizontalAccuracy * sample.horizontalAccuracy,
      );
      final ratio = (combinedPositionError / distance).clamp(0.0, 1.0);
      final accuracyDegrees = math.asin(ratio) * 180 / math.pi;
      if (accuracyDegrees <= _maximumAccuracyDegrees) {
        _lastEstimate = _StoredEstimate(
          CourseHeadingEstimate(
            degrees: _bearingDegrees(reference, sample),
            accuracyDegrees: accuracyDegrees,
          ),
          now,
        );
      }
    }
    return _currentEstimate(now);
  }

  void reset() {
    _reference = null;
    _lastEstimate = null;
  }

  CourseHeadingEstimate? _currentEstimate(DateTime now) {
    final stored = _lastEstimate;
    if (stored == null || now.difference(stored.recordedAt) > _maximumAge) {
      return null;
    }
    return stored.estimate;
  }

  double _distanceMeters(TelemetrySample first, TelemetrySample second) {
    const metersPerDegree = 111000.0;
    final latitude = (first.latitude - second.latitude) * metersPerDegree;
    final longitude = (first.longitude - second.longitude) *
        metersPerDegree *
        math.cos(first.latitude * math.pi / 180);
    return math.sqrt(latitude * latitude + longitude * longitude);
  }

  double _bearingDegrees(TelemetrySample from, TelemetrySample to) {
    final deltaLongitude = (to.longitude - from.longitude) * math.pi / 180;
    final latitude1 = from.latitude * math.pi / 180;
    final latitude2 = to.latitude * math.pi / 180;
    final y = math.sin(deltaLongitude) * math.cos(latitude2);
    final x = math.cos(latitude1) * math.sin(latitude2) -
        math.sin(latitude1) * math.cos(latitude2) * math.cos(deltaLongitude);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}

class _StoredEstimate {
  const _StoredEstimate(this.estimate, this.recordedAt);

  final CourseHeadingEstimate estimate;
  final DateTime recordedAt;
}
