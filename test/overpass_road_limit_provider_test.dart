import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/data/road_limit/overpass_road_limit_provider.dart';

void main() {
  group('parseMaxSpeed', () {
    test('aceita km/h numérico e converte mph', () {
      expect(OverpassRoadLimitProvider.parseMaxSpeed('80'), 80);
      expect(OverpassRoadLimitProvider.parseMaxSpeed('50 km/h'), 50);
      expect(OverpassRoadLimitProvider.parseMaxSpeed('30 mph'), 48);
    });

    test('rejeita valores especiais e condicionais', () {
      expect(OverpassRoadLimitProvider.parseMaxSpeed('signals'), isNull);
      expect(OverpassRoadLimitProvider.parseMaxSpeed('80 @ (22:00-06:00)'),
          isNull);
      expect(OverpassRoadLimitProvider.parseMaxSpeed('50;80'), isNull);
    });
  });
}
