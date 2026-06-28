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

  test('rejeita posição horizontal imprecisa', () {
    expect(
      RoadMatcher().select(
        sample: const TelemetrySample(
          latitude: -23.5,
          longitude: -46.6,
          speedMetersPerSecond: 12,
          speedAccuracy: 1,
          horizontalAccuracy: 21,
          heading: 90,
          headingAccuracy: 5,
        ),
        candidates: const [road],
      ),
      isNull,
    );
  });

  test('identifica via nomeada sem limite', () {
    final match = RoadMatcher().select(
      sample: _sample(),
      candidates: const [
        RoadSegment(
          id: 8,
          points: [
            GeoPoint(-23.5, -46.6002),
            GeoPoint(-23.5, -46.5998),
          ],
          tags: {'name': 'Rua sem limite'},
        ),
      ],
    );

    expect(match?.wayId, 8);
    expect(match?.name, 'Rua sem limite');
    expect(match?.limit, isNull);
  });

  test('usa referência quando a via não possui nome', () {
    final match = RoadMatcher().select(
      sample: _sample(),
      candidates: const [
        RoadSegment(
          id: 9,
          points: [
            GeoPoint(-23.5, -46.6002),
            GeoPoint(-23.5, -46.5998),
          ],
          tags: {'ref': 'BR-101'},
        ),
      ],
    );

    expect(match?.name, 'BR-101');
  });

  test('aceita via bidirecional com deslocamento e rumo realistas', () {
    final match = RoadMatcher().select(
      sample: _sample(latitude: -23.50005, heading: 100),
      candidates: const [road],
    );

    expect(match?.wayId, road.id);
  });

  test('aceita o sentido inverso de via bidirecional', () {
    final match = RoadMatcher().select(
      sample: _sample(heading: 270),
      candidates: const [road],
    );

    expect(match?.wayId, road.id);
    expect(match?.limit, 30);
  });

  test('usa o segmento local de uma via curva', () {
    final match = RoadMatcher().select(
      sample: _sample(
        latitude: -23.4999,
        longitude: -46.5998,
        heading: 0,
      ),
      candidates: const [
        RoadSegment(
          id: 12,
          points: [
            GeoPoint(-23.5, -46.6002),
            GeoPoint(-23.5, -46.5998),
            GeoPoint(-23.4997, -46.5998),
          ],
          tags: {'name': 'Curva'},
        ),
      ],
    );

    expect(match?.wayId, 12);
  });

  test('incerteza da velocidade não impede identificar a via', () {
    final match = RoadMatcher().select(
      sample: _sample(speedAccuracy: 4),
      candidates: const [road],
    );

    expect(match?.wayId, road.id);
  });

  test('sem rumo aceita apenas via inequivocamente mais próxima', () {
    final match = RoadMatcher().select(
      sample: _sample(heading: null, headingAccuracy: null),
      candidates: const [
        road,
        RoadSegment(
          id: 13,
          points: [
            GeoPoint(-23.5002, -46.6002),
            GeoPoint(-23.5002, -46.5998),
          ],
          tags: {'name': 'Via distante'},
        ),
      ],
    );

    expect(match?.wayId, road.id);
  });

  test('sem rumo rejeita vias próximas ambíguas', () {
    final match = RoadMatcher().select(
      sample: _sample(heading: null, headingAccuracy: null),
      candidates: const [
        road,
        RoadSegment(
          id: 14,
          points: [
            GeoPoint(-23.50004, -46.6002),
            GeoPoint(-23.50004, -46.5998),
          ],
          tags: {'name': 'Via paralela'},
        ),
      ],
    );

    expect(match, isNull);
  });
}

TelemetrySample _sample({
  double latitude = -23.5,
  double longitude = -46.6,
  double? heading = 90,
  double? headingAccuracy = 5,
  double speedAccuracy = 1,
  double horizontalAccuracy = 5,
}) =>
    TelemetrySample(
      latitude: latitude,
      longitude: longitude,
      speedMetersPerSecond: 8,
      speedAccuracy: speedAccuracy,
      horizontalAccuracy: horizontalAccuracy,
      heading: heading,
      headingAccuracy: headingAccuracy,
    );
