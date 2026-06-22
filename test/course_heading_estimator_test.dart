import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/domain/services/course_heading_estimator.dart';
import 'package:speedometer/domain/telemetry/telemetry_dependencies.dart';

void main() {
  test('estima rumo leste após deslocamento suficiente e preciso', () {
    final estimator = CourseHeadingEstimator();
    final now = DateTime(2026, 1, 1, 12);

    expect(estimator.estimate(_sample(-46.6003), now), isNull);
    final estimate = estimator.estimate(
        _sample(-46.6000), now.add(const Duration(seconds: 2)));

    expect(estimate?.degrees, closeTo(90, 1));
    expect(estimate?.accuracyDegrees, lessThanOrEqualTo(20));
  });

  test('não estima rumo quando a incerteza de posição é alta', () {
    final estimator = CourseHeadingEstimator();
    final now = DateTime(2026, 1, 1, 12);

    estimator.estimate(_sample(-46.6003, accuracy: 15), now);
    expect(
      estimator.estimate(
          _sample(-46.6000, accuracy: 15), now.add(const Duration(seconds: 2))),
      isNull,
    );
  });

  test('não reutiliza rumo quando a precisão horizontal não foi informada', () {
    final estimator = CourseHeadingEstimator();
    final now = DateTime(2026, 1, 1, 12);

    estimator.estimate(_sample(-46.6003), now);
    expect(
      estimator.estimate(
          _sample(-46.6000), now.add(const Duration(seconds: 1))),
      isNotNull,
    );
    expect(
      estimator.estimate(
          _sample(-46.59995, accuracy: 0), now.add(const Duration(seconds: 2))),
      isNull,
    );
  });

  test('expira rumo calculado depois de dois segundos', () {
    final estimator = CourseHeadingEstimator();
    final now = DateTime(2026, 1, 1, 12);

    estimator.estimate(_sample(-46.6003), now);
    expect(
      estimator.estimate(
          _sample(-46.6000), now.add(const Duration(seconds: 1))),
      isNotNull,
    );
    expect(
      estimator.estimate(
          _sample(-46.59995), now.add(const Duration(seconds: 4))),
      isNull,
    );
  });
}

TelemetrySample _sample(double longitude, {double accuracy = 5}) =>
    TelemetrySample(
      latitude: -23.5,
      longitude: longitude,
      speedMetersPerSecond: 12,
      speedAccuracy: 1,
      horizontalAccuracy: accuracy,
      heading: 90,
      headingAccuracy: 30,
      timestamp: DateTime(2026, 1, 1, 12),
    );
