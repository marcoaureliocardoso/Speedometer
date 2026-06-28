import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/telemetry/road_matcher.dart';
import '../../domain/telemetry/telemetry_dependencies.dart';

/// Cliente único do Overpass: evita consultas concorrentes e protege o serviço
/// público com um circuito aberto temporário após falhas repetidas.
class OverpassRoadLimitProvider implements RoadLimitDataSource {
  OverpassRoadLimitProvider({
    http.Client? client,
    DateTime Function()? clock,
    List<Uri>? endpoints,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now,
        _endpoints = List.unmodifiable(endpoints ?? defaultEndpoints);

  static final defaultEndpoints = <Uri>[
    Uri.parse('https://overpass-api.de/api/interpreter'),
    Uri.parse('https://maps.mail.ru/osm/tools/overpass/api/interpreter'),
  ];

  final http.Client _client;
  final DateTime Function() _clock;
  final List<Uri> _endpoints;
  final Map<Uri, _EndpointState> _endpointStates = {};
  Future<List<RoadSegment>>? _inFlight;

  @override
  Future<List<RoadSegment>> fetchCandidates({
    required double latitude,
    required double longitude,
  }) {
    final request = _inFlight;
    if (request != null) return request;
    final future = _request(latitude, longitude);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<List<RoadSegment>> _request(double latitude, double longitude) async {
    final query = '''
[out:json][timeout:6];
way(around:40,$latitude,$longitude)[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)\$"];
out tags geom;
''';
    RoadDataUnavailable? lastFailure;
    for (final endpoint in _endpoints) {
      final state = _endpointStates.putIfAbsent(endpoint, _EndpointState.new);
      final openUntil = state.circuitOpenUntil;
      if (openUntil != null && _clock().isBefore(openUntil)) continue;
      try {
        final response = await _client.post(
          endpoint,
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'User-Agent': 'speedometer/1.0',
          },
          body: {'data': query},
        ).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final roads = _decode(response.body);
          _recordSuccess(state);
          return roads;
        }
        final failure =
            RoadDataUnavailable('Overpass retornou ${response.statusCode}.');
        if (!_isRetryable(response.statusCode)) throw failure;
        _recordFailure(state);
        lastFailure = failure;
      } catch (error) {
        if (error is RoadDataUnavailable &&
            error.message.startsWith('Overpass retornou ') &&
            !_isRetryableStatusMessage(error.message)) {
          rethrow;
        }
        _recordFailure(state);
        lastFailure = error is RoadDataUnavailable
            ? error
            : RoadDataUnavailable('Consulta online indisponível: $error');
      }
    }
    throw lastFailure ??
        const RoadDataUnavailable('Circuitos do Overpass abertos.');
  }

  List<RoadSegment> _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['elements'] is! List) {
      throw const RoadDataUnavailable('Resposta inválida do Overpass.');
    }
    return (decoded['elements'] as List)
        .map(_toSegment)
        .whereType<RoadSegment>()
        .toList(growable: false);
  }

  bool _isRetryable(int statusCode) =>
      const {406, 408, 429}.contains(statusCode) || statusCode >= 500;

  bool _isRetryableStatusMessage(String message) {
    final match = RegExp(r'(\d+)\.$').firstMatch(message);
    return match != null && _isRetryable(int.parse(match.group(1)!));
  }

  void _recordSuccess(_EndpointState state) {
    state
      ..consecutiveFailures = 0
      ..circuitOpenUntil = null;
  }

  void _recordFailure(_EndpointState state) {
    state.consecutiveFailures++;
    if (state.consecutiveFailures >= 3) {
      state
        ..consecutiveFailures = 0
        ..circuitOpenUntil = _clock().add(const Duration(minutes: 5));
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
            ? GeoPoint((point['lat'] as num).toDouble(),
                (point['lon'] as num).toDouble())
            : null)
        .whereType<GeoPoint>()
        .toList(growable: false);
    return points.length < 2
        ? null
        : RoadSegment(
            id: (value['id'] as num).toInt(), points: points, tags: tags);
  }

  static int? parseMaxSpeed(String? value) =>
      RoadMatcher.parseMaxSpeed(value, const {});

  @override
  void dispose() => _client.close();
}

class _EndpointState {
  int consecutiveFailures = 0;
  DateTime? circuitOpenUntil;
}

class RoadDataUnavailable implements Exception {
  const RoadDataUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}
