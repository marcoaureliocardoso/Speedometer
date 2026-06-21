import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/telemetry/road_matcher.dart';
import '../../domain/telemetry/telemetry_dependencies.dart';

/// Cliente único do Overpass: evita consultas concorrentes e protege o serviço
/// público com um circuito aberto temporário após falhas repetidas.
class OverpassRoadLimitProvider implements RoadLimitDataSource {
  OverpassRoadLimitProvider({http.Client? client, DateTime Function()? clock})
      : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _clock;
  Future<List<RoadSegment>>? _inFlight;
  int _consecutiveFailures = 0;
  DateTime? _circuitOpenUntil;

  @override
  Future<List<RoadSegment>> fetchCandidates({
    required double latitude,
    required double longitude,
  }) {
    final until = _circuitOpenUntil;
    if (until != null && _clock().isBefore(until)) {
      return Future.error(const RoadDataUnavailable('Circuito do Overpass aberto.'));
    }
    final request = _inFlight;
    if (request != null) return request;
    final future = _request(latitude, longitude);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<List<RoadSegment>> _request(double latitude, double longitude) async {
    final query = '''
[out:json][timeout:5];
(
  way(around:30,$latitude,$longitude)[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)\$"][maxspeed];
  way(around:30,$latitude,$longitude)[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)\$"]["maxspeed:forward"];
  way(around:30,$latitude,$longitude)[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)\$"]["maxspeed:backward"];
);
out tags geom;
''';
    try {
      final response = await _client
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) throw RoadDataUnavailable('Overpass retornou ${response.statusCode}.');
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = decoded['elements'];
      if (elements is! List) throw const RoadDataUnavailable('Resposta inválida do Overpass.');
      _consecutiveFailures = 0;
      return elements.map(_toSegment).whereType<RoadSegment>().toList(growable: false);
    } catch (error) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3) {
        _circuitOpenUntil = _clock().add(const Duration(minutes: 5));
        _consecutiveFailures = 0;
      }
      if (error is RoadDataUnavailable) rethrow;
      throw RoadDataUnavailable('Consulta online indisponível: $error');
    }
  }

  RoadSegment? _toSegment(dynamic value) {
    if (value is! Map<String, dynamic> || value['id'] is! num) return null;
    final rawTags = value['tags'];
    final rawGeometry = value['geometry'];
    if (rawTags is! Map || rawGeometry is! List) return null;
    final tags = <String, String>{};
    rawTags.forEach((key, entry) {
      if (key is String && entry != null) tags[key] = entry.toString();
    });
    if (const {'no', 'private'}.contains(tags['access']) ||
        const {'no'}.contains(tags['motor_vehicle']) ||
        const {'no'}.contains(tags['motorcar'])) {
      return null;
    }
    final points = rawGeometry
        .whereType<Map>()
        .map((point) => (point['lat'] is num && point['lon'] is num)
            ? GeoPoint((point['lat'] as num).toDouble(), (point['lon'] as num).toDouble())
            : null)
        .whereType<GeoPoint>()
        .toList(growable: false);
    return points.length < 2 ? null : RoadSegment(id: (value['id'] as num).toInt(), points: points, tags: tags);
  }

  static int? parseMaxSpeed(String? value) => RoadMatcher.parseMaxSpeed(value, const {});

  @override
  void dispose() => _client.close();
}

class RoadDataUnavailable implements Exception {
  const RoadDataUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}
