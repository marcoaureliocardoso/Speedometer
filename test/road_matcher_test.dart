import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/domain/telemetry/road_matcher.dart';
import 'package:speedometer/domain/telemetry/telemetry_dependencies.dart';

void main() {
  const road = RoadSegment(
    id: 7,
    points: [GeoPoint(-23.5, -46.6002), GeoPoint(-23.5, -46.5998)],
    tags: {'maxspeed:forward': '50', 'maxspeed:backward': '30'},
  );

  test('seleciona limite direcional para via alinhada', () {
    final match = RoadMatcher().select(
      sample: const TelemetrySample(
        latitude: -23.5,
        longitude: -46.6,
        speedMetersPerSecond: 12,
        speedAccuracy: 1,
        horizontalAccuracy: 5,
        heading: 90,
        headingAccuracy: 5,
      ),
      candidates: const [road],
    );
    expect(match?.wayId, 7);
    expect(match?.limit, 50);
  });

  test('rejeita GPS ou rumo imprecisos', () {
    expect(
      RoadMatcher().select(
        sample: const TelemetrySample(
          latitude: -23.5, longitude: -46.6, speedMetersPerSecond: 12,
          speedAccuracy: 2, horizontalAccuracy: 5, heading: 90, headingAccuracy: 5,
        ),
        candidates: const [road],
      ),
      isNull,
    );
  });
}
