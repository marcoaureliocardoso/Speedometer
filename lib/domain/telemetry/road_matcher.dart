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
    if (sample.horizontalAccuracy > 20) return null;
    final hasReliableHeading =
        sample.heading != null && (sample.headingAccuracy ?? 999) <= 20;
    final scored = <_ScoredRoad>[];
    for (final road in candidates) {
      if (road.points.length < 2) continue;
      final geometry = _nearestGeometry(sample, road.points);
      final oneway = road.tags['oneway'];
      if (hasReliableHeading) {
        final heading = sample.heading!;
        final directionDifference =
            _roadDirectionDifference(heading, geometry.heading, oneway);
        if (geometry.distance > 25 ||
            directionDifference == double.infinity ||
            directionDifference > 90) {
          continue;
        }
        final score = 60 * (1 - geometry.distance / 25) +
            30 * (1 - directionDifference / 90) +
            (previousWayId == road.id ? 10 : 0);
        final minimum = previousWayId == road.id ? 35 : 45;
        if (score < minimum) continue;
        scored.add(_ScoredRoad(
          road,
          _limitForDirection(road, heading, geometry.heading),
          geometry.distance,
          score,
        ));
      } else if (geometry.distance <= 15) {
        scored.add(_ScoredRoad(
          road,
          _undirectedLimit(road),
          geometry.distance,
          60 * (1 - geometry.distance / 25) +
              (previousWayId == road.id ? 10 : 0),
        ));
      }
    }
    scored.sort((first, second) => second.score.compareTo(first.score));
    if (scored.isEmpty) return null;
    if (scored.length > 1) {
      final lead = hasReliableHeading
          ? scored.first.score - scored[1].score
          : scored[1].distance - scored.first.distance;
      if (lead < (hasReliableHeading ? 8 : 10)) return null;
    }
    final match = scored.first;
    final name = match.road.tags['name']?.trim();
    final reference = match.road.tags['ref']?.trim();
    return RoadMatch(
      wayId: match.road.id,
      limit: match.limit,
      name: name?.isNotEmpty == true
          ? name
          : reference?.isNotEmpty == true
              ? reference
              : null,
      distanceMeters: match.distance,
    );
  }

  int? _limitForDirection(
      RoadSegment road, double heading, double roadHeading) {
    final isForward = _angularDifference(heading, roadHeading) <= 90;
    final raw = isForward
        ? road.tags['maxspeed:forward'] ?? road.tags['maxspeed']
        : road.tags['maxspeed:backward'] ?? road.tags['maxspeed'];
    return parseMaxSpeed(raw, road.tags);
  }

  int? _undirectedLimit(RoadSegment road) =>
      parseMaxSpeed(road.tags['maxspeed'], road.tags);

  static int? parseMaxSpeed(String? value, Map<String, String> tags) {
    if (value == null ||
        tags.containsKey('maxspeed:conditional') ||
        tags.containsKey('maxspeed:variable') ||
        tags.containsKey('maxspeed:lanes')) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized.contains(';') ||
        normalized.contains('@') ||
        const {'signals', 'none', 'variable'}.contains(normalized)) {
      return null;
    }
    final mph = RegExp(r'^(\d+(?:[.,]\d+)?)\s*mph$').firstMatch(normalized);
    if (mph != null) {
      return (double.parse(mph.group(1)!.replaceAll(',', '.')) * 1.609344)
          .round();
    }
    final kmh =
        RegExp(r'^(\d+(?:[.,]\d+)?)(?:\s*km/h)?$').firstMatch(normalized);
    return kmh == null
        ? null
        : double.parse(kmh.group(1)!.replaceAll(',', '.')).round();
  }

  _RoadGeometry _nearestGeometry(
      TelemetrySample sample, List<GeoPoint> points) {
    var nearest = const _RoadGeometry(double.infinity, 0);
    for (var index = 1; index < points.length; index++) {
      final distance = _pointToSegmentMeters(
        GeoPoint(sample.latitude, sample.longitude),
        points[index - 1],
        points[index],
      );
      if (distance < nearest.distance) {
        nearest =
            _RoadGeometry(distance, _heading(points[index - 1], points[index]));
      }
    }
    return nearest;
  }

  double _roadDirectionDifference(
      double vehicleHeading, double roadHeading, String? oneway) {
    final forward = _angularDifference(vehicleHeading, roadHeading);
    final backward =
        _angularDifference(vehicleHeading, (roadHeading + 180) % 360);
    if (oneway == 'yes') return forward <= 90 ? forward : double.infinity;
    if (oneway == '-1') return backward <= 90 ? backward : double.infinity;
    return math.min(forward, backward);
  }

  double _pointToSegmentMeters(GeoPoint point, GeoPoint a, GeoPoint b) {
    const earthRadius = 6371000.0;
    final latitudeRadians = point.latitude * math.pi / 180;
    double x(GeoPoint value) =>
        (value.longitude - point.longitude) *
        math.pi /
        180 *
        earthRadius *
        math.cos(latitudeRadians);
    double y(GeoPoint value) =>
        (value.latitude - point.latitude) * math.pi / 180 * earthRadius;
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

  double _angularDifference(double first, double second) =>
      (first - second).abs().clamp(0, 360) > 180
          ? 360 - (first - second).abs()
          : (first - second).abs();
}

class _RoadGeometry {
  const _RoadGeometry(this.distance, this.heading);

  final double distance;
  final double heading;
}

class _ScoredRoad {
  const _ScoredRoad(this.road, this.limit, this.distance, this.score);
  final RoadSegment road;
  final int? limit;
  final double distance;
  final double score;
}
