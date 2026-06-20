import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/telemetry/telemetry_dependencies.dart';

class OverpassRoadLimitProvider implements RoadLimitDataSource {
  OverpassRoadLimitProvider({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<int?> fetchLimit(
      {required double latitude, required double longitude}) async {
    final query = '''
[out:json][timeout:5];
(
  way(around:30,$latitude,$longitude)[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)\$"][maxspeed];
  way(around:30,$latitude,$longitude)[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)\$"]["maxspeed:forward"];
  way(around:30,$latitude,$longitude)[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)\$"]["maxspeed:backward"];
);
out tags 1;
''';
    final response = await _client.post(
      Uri.parse('https://overpass-api.de/api/interpreter'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'data': query},
    ).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = decoded['elements'];
    if (elements is! List) return null;
    for (final element in elements) {
      if (element is! Map<String, dynamic>) continue;
      final tags = element['tags'];
      if (tags is Map<String, dynamic>) {
        final parsed = parseMaxSpeed(tags['maxspeed']?.toString());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static int? parseMaxSpeed(String? value) {
    if (value == null) return null;
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

  @override
  void dispose() => _client.close();
}
