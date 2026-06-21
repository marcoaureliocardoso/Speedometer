import 'dart:math' as math;

import '../telemetry/telemetry_dependencies.dart';

/// Seleciona uma via por distância, rumo e continuidade. A confirmação de duas
/// leituras é feita pelo controlador, para que a regra não dependa da rede.
class RoadMatcher {
  RoadMatch? select({
    required TelemetrySample sample,
    required List<RoadSegment> candidates,
    int? previousWayId,
  }) {
    if (sample.horizontalAccuracy > 15 || sample.speedAccuracy > 1.5) {
      return null;
    }
    final heading = sample.heading;
    if (heading == null || (sample.headingAccuracy ?? 999) > 20) return null;

    _ScoredRoad? best;
    for (final road in candidates) {
      final limit = _limitForDirection(road, heading);
      if (limit == null || road.points.length < 2) continue;
      final geometryHeading = _heading(road.points.first, road.points.last);
      final directionDifference = _angularDifference(heading, geometryHeading);
      final oneway = road.tags['oneway'];
      if (oneway == 'yes' && directionDifference > 90) continue;
      if (oneway == '-1' && _angularDifference(heading, (geometryHeading + 180) % 360) > 90) {
        continue;
      }
      final distance = _distanceToRoad(sample, road.points);
      if (distance > 15) continue;
      final score =
          40 * math.max(0, 1 - distance / 15) +
          30 * math.max(0, 1 - directionDifference / 45) +
          (previousWayId == road.id ? 20 : 0) +
          ((oneway == 'yes' || oneway == '-1') ? 10 : 0);
      // A projeção geodésica pode introduzir frações mínimas no rumo de uma
      // via perfeitamente alinhada; 69,5 preserva o limiar sem rejeitar esse
      // artefato numérico.
      if (score < 69.5 || (best != null && score <= best.score)) continue;
      best = _ScoredRoad(road, limit, distance, score.toDouble());
    }
    final match = best;
    return match == null
        ? null
        : RoadMatch(
            wayId: match.road.id,
            limit: match.limit,
            name: match.road.tags['name'],
            distanceMeters: match.distance,
          );
  }

  int? _limitForDirection(RoadSegment road, double heading) {
    final forward = _heading(road.points.first, road.points.last);
    final isForward = _angularDifference(heading, forward) <= 90;
    final raw = isForward
        ? road.tags['maxspeed:forward'] ?? road.tags['maxspeed']
        : road.tags['maxspeed:backward'] ?? road.tags['maxspeed'];
    return parseMaxSpeed(raw, road.tags);
  }

  static int? parseMaxSpeed(String? value, Map<String, String> tags) {
    if (value == null ||
        tags.containsKey('maxspeed:conditional') ||
        tags.containsKey('maxspeed:variable') ||
        tags.containsKey('maxspeed:lanes')) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || normalized.contains(';') || normalized.contains('@') ||
        const {'signals', 'none', 'variable'}.contains(normalized)) {
      return null;
    }
    final mph = RegExp(r'^(\d+(?:[.,]\d+)?)\s*mph$').firstMatch(normalized);
    if (mph != null) {
      return (double.parse(mph.group(1)!.replaceAll(',', '.')) * 1.609344).round();
    }
    final kmh = RegExp(r'^(\d+(?:[.,]\d+)?)(?:\s*km/h)?$').firstMatch(normalized);
    return kmh == null ? null : double.parse(kmh.group(1)!.replaceAll(',', '.')).round();
  }

  double _distanceToRoad(TelemetrySample sample, List<GeoPoint> points) {
    var shortest = double.infinity;
    for (var index = 1; index < points.length; index++) {
      shortest = math.min(shortest, _pointToSegmentMeters(
        GeoPoint(sample.latitude, sample.longitude), points[index - 1], points[index]));
    }
    return shortest;
  }

  double _pointToSegmentMeters(GeoPoint point, GeoPoint a, GeoPoint b) {
    const earthRadius = 6371000.0;
    final latitudeRadians = point.latitude * math.pi / 180;
    double x(GeoPoint value) => (value.longitude - point.longitude) * math.pi / 180 * earthRadius * math.cos(latitudeRadians);
    double y(GeoPoint value) => (value.latitude - point.latitude) * math.pi / 180 * earthRadius;
    final ax = x(a), ay = y(a), bx = x(b), by = y(b);
    final lengthSquared = (bx - ax) * (bx - ax) + (by - ay) * (by - ay);
    if (lengthSquared == 0) return math.sqrt(ax * ax + ay * ay);
    final projection = ((-ax) * (bx - ax) + (-ay) * (by - ay)) / lengthSquared;
    final t = projection.clamp(0.0, 1.0);
    final dx = ax + (bx - ax) * t, dy = ay + (by - ay) * t;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _heading(GeoPoint from, GeoPoint to) {
    final deltaLongitude = (to.longitude - from.longitude) * math.pi / 180;
    final latitude1 = from.latitude * math.pi / 180;
    final latitude2 = to.latitude * math.pi / 180;
    final y = math.sin(deltaLongitude) * math.cos(latitude2);
    final x = math.cos(latitude1) * math.sin(latitude2) -
        math.sin(latitude1) * math.cos(latitude2) * math.cos(deltaLongitude);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _angularDifference(double first, double second) => (first - second).abs().clamp(0, 360) > 180
      ? 360 - (first - second).abs()
      : (first - second).abs();
}

class _ScoredRoad {
  const _ScoredRoad(this.road, this.limit, this.distance, this.score);
  final RoadSegment road;
  final int limit;
  final double distance;
  final double score;
}
