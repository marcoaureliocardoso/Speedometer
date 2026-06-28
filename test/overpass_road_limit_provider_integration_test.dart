import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:speedometer/data/road_limit/overpass_road_limit_provider.dart';

void main() {
  test('mapeia geometria e descarta vias sem acesso motorizado', () async {
    late http.Request captured;
    final provider = OverpassRoadLimitProvider(
      endpoints: [Uri.parse('https://primary.test/interpreter')],
      client: MockClient((request) async {
        captured = request;
        return http.Response('''
          {"elements":[
            {"id":10,"tags":{"maxspeed":"60","name":"Via válida"},"geometry":[{"lat":-23.5,"lon":-46.6},{"lat":-23.5,"lon":-46.59}]},
            {"id":11,"tags":{"maxspeed":"50","access":"private"},"geometry":[{"lat":-23.5,"lon":-46.6},{"lat":-23.5,"lon":-46.59}]}
          ]}
        ''', 200);
      }),
    );

    final roads =
        await provider.fetchCandidates(latitude: -23.5, longitude: -46.6);

    expect(captured.method, 'POST');
    expect(captured.url.host, 'primary.test');
    final query = Uri.splitQueryString(captured.body)['data']!;
    expect(query, contains('around:40'));
    expect(query, isNot(contains('[maxspeed]')));
    expect(query, contains('out tags geom'));
    expect(captured.headers['accept'], 'application/json');
    expect(captured.headers['user-agent'], startsWith('speedometer/'));
    expect(roads, hasLength(1));
    expect(roads.single.id, 10);
    expect(roads.single.points, hasLength(2));
  });

  test('abre o circuito após três falhas sem fazer uma quarta requisição',
      () async {
    var calls = 0;
    var now = DateTime(2026, 1, 1);
    final provider = OverpassRoadLimitProvider(
      clock: () => now,
      endpoints: [Uri.parse('https://primary.test/interpreter')],
      client: MockClient((_) async {
        calls++;
        throw StateError('sem rede');
      }),
    );

    for (var attempt = 0; attempt < 3; attempt++) {
      await expectLater(
        provider.fetchCandidates(latitude: -23.5, longitude: -46.6),
        throwsA(isA<RoadDataUnavailable>()),
      );
    }
    await expectLater(
      provider.fetchCandidates(latitude: -23.5, longitude: -46.6),
      throwsA(isA<RoadDataUnavailable>()),
    );
    expect(calls, 3);

    now = now.add(const Duration(minutes: 5));
    await expectLater(
      provider.fetchCandidates(latitude: -23.5, longitude: -46.6),
      throwsA(isA<RoadDataUnavailable>()),
    );
    expect(calls, 4);
  });

  test('compartilha uma única chamada simultânea ao Overpass', () async {
    final response = Completer<http.Response>();
    var calls = 0;
    final provider = OverpassRoadLimitProvider(
      endpoints: [Uri.parse('https://primary.test/interpreter')],
      client: MockClient((_) {
        calls++;
        return response.future;
      }),
    );

    final first = provider.fetchCandidates(latitude: -23.5, longitude: -46.6);
    final second = provider.fetchCandidates(latitude: -23.5, longitude: -46.6);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    response.complete(http.Response('{"elements":[]}', 200));
    await Future.wait([first, second]);
  });

  test('usa endpoint secundário depois de 406', () async {
    final hosts = <String>[];
    final provider = OverpassRoadLimitProvider(
      endpoints: [
        Uri.parse('https://primary.test/interpreter'),
        Uri.parse('https://secondary.test/interpreter'),
      ],
      client: MockClient((request) async {
        hosts.add(request.url.host);
        return request.url.host == 'primary.test'
            ? http.Response('not acceptable', 406)
            : http.Response('{"elements":[]}', 200);
      }),
    );

    await provider.fetchCandidates(latitude: -23.5, longitude: -46.6);

    expect(hosts, ['primary.test', 'secondary.test']);
  });

  test('não mascara erro de consulta com failover', () async {
    final hosts = <String>[];
    final provider = OverpassRoadLimitProvider(
      endpoints: [
        Uri.parse('https://primary.test/interpreter'),
        Uri.parse('https://secondary.test/interpreter'),
      ],
      client: MockClient((request) async {
        hosts.add(request.url.host);
        return http.Response('bad request', 400);
      }),
    );

    await expectLater(
      provider.fetchCandidates(latitude: -23.5, longitude: -46.6),
      throwsA(isA<RoadDataUnavailable>()),
    );
    expect(hosts, ['primary.test']);
  });

  test('resposta vazia válida não abre o circuito', () async {
    var calls = 0;
    final provider = OverpassRoadLimitProvider(
      endpoints: [Uri.parse('https://primary.test/interpreter')],
      client: MockClient((_) async {
        calls++;
        return http.Response('{"elements":[]}', 200);
      }),
    );

    for (var index = 0; index < 4; index++) {
      expect(
        await provider.fetchCandidates(latitude: -23.5, longitude: -46.6),
        isEmpty,
      );
    }

    expect(calls, 4);
  });
}
