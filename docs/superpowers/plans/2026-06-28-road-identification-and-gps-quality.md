# Road Identification and GPS Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exibir a via atual mesmo sem `maxspeed`, tornar o pareamento robusto em vias bidirecionais e separar falhas de posição, velocidade, rumo e rede.

**Architecture:** O Overpass continua como fonte única, mas passa a consultar todas as vias motorizáveis e a tentar dois endpoints sequencialmente. O matcher usa o segmento local mais próximo, aceita limite opcional e tem uma recuperação conservadora por distância quando não há rumo confiável. O controlador mantém nome e limite como estados independentes e expõe diagnósticos específicos.

**Tech Stack:** Flutter/Dart, `http`, Geolocator, OpenStreetMap Overpass QL, `flutter_test`.

---

## File map

- Modify: `lib/domain/telemetry/telemetry_dependencies.dart` — permitir limite opcional em `RoadMatch`.
- Modify: `lib/domain/telemetry/road_matcher.dart` — pareamento local, bidirecional, por confiança e sem dependência de `speedAccuracy`.
- Modify: `lib/data/road_limit/overpass_road_limit_provider.dart` — consulta ampla, headers, failover e circuito por endpoint.
- Modify: `lib/presentation/controllers/telemetry_controller.dart` — separar estados de qualidade e conservar via sem limite.
- Modify: `lib/presentation/pages/dashboard_page.dart` — mostrar via sem limite e rótulos de diagnóstico específicos.
- Modify: `test/road_matcher_test.dart` — cobrir sentidos, curvas, ausência de limite e fallback por distância.
- Modify: `test/overpass_road_limit_provider_integration_test.dart` — cobrir consulta ampla, headers, failover e resposta vazia.
- Modify: `test/telemetry_controller_test.dart` — cobrir via sem limite e independência da incerteza de velocidade.
- Modify: `test/limit_status_test.dart` — cobrir interface e semântica da via sem limite.

### Task 1: Make road identity independent from speed limit

**Files:**
- Modify: `lib/domain/telemetry/telemetry_dependencies.dart:49-63`
- Modify: `test/road_matcher_test.dart`

- [ ] **Step 1: Write failing model and matcher tests**

Add tests that construct a named road without `maxspeed`, expect a non-null
match with a null limit, and expect `ref` to be used when `name` is absent:

```dart
const eastWestRoad = RoadSegment(
  id: 7,
  points: [
    GeoPoint(-23.5, -46.6002),
    GeoPoint(-23.5, -46.5998),
  ],
  tags: {'name': 'Via Leste-Oeste', 'maxspeed': '50'},
);

TelemetrySample sample({
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

test('identifica via nomeada sem limite', () {
  final match = RoadMatcher().select(
    sample: sample(heading: 90),
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
    sample: sample(heading: 90),
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
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```powershell
flutter test test/road_matcher_test.dart
```

Expected: compilation fails because `RoadMatch.limit` is required as `int`, or
the matcher returns null because it discards roads without a parsed limit.

- [ ] **Step 3: Make `RoadMatch.limit` nullable**

Change the entity to:

```dart
class RoadMatch {
  const RoadMatch({
    required this.wayId,
    required this.limit,
    required this.name,
    required this.distanceMeters,
  });

  final int wayId;
  final int? limit;
  final String? name;
  final double distanceMeters;
}
```

In `RoadMatcher.select`, stop discarding a road when `_limitForDirection`
returns null, and construct the name as:

```dart
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
```

Change `_ScoredRoad.limit` to `int?`.

- [ ] **Step 4: Run the focused tests and verify pass**

Run:

```powershell
flutter test test/road_matcher_test.dart
```

Expected: the new name/ref tests pass; existing directional limit test remains
green.

- [ ] **Step 5: Commit**

```powershell
git add lib/domain/telemetry/telemetry_dependencies.dart lib/domain/telemetry/road_matcher.dart test/road_matcher_test.dart
git commit -m "refactor: desacopla via de limite de velocidade"
```

### Task 2: Replace the practically unreachable matcher score

**Files:**
- Modify: `lib/domain/telemetry/road_matcher.dart`
- Modify: `test/road_matcher_test.dart`

- [ ] **Step 1: Write failing matching tests**

Use the `sample` helper and `eastWestRoad` fixture added in Task 1. Add tests
for realistic offset, reverse travel, curved geometry, speed uncertainty,
distance-only matching, and ambiguity:

```dart
test('aceita via bidirecional com deslocamento e rumo realistas', () {
  final match = RoadMatcher().select(
    sample: sample(latitude: -23.50005, heading: 100),
    candidates: const [eastWestRoad],
  );
  expect(match?.wayId, eastWestRoad.id);
});

test('aceita o sentido inverso de via bidirecional', () {
  final match = RoadMatcher().select(
    sample: sample(heading: 270),
    candidates: const [eastWestRoad],
  );
  expect(match?.wayId, eastWestRoad.id);
});

test('usa o segmento local de uma via curva', () {
  final match = RoadMatcher().select(
    sample: sample(
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
    sample: sample(speedAccuracy: 4),
    candidates: const [eastWestRoad],
  );
  expect(match?.wayId, eastWestRoad.id);
});

test('sem rumo aceita apenas via inequivocamente mais próxima', () {
  final match = RoadMatcher().select(
    sample: sample(heading: null, headingAccuracy: null),
    candidates: const [
      eastWestRoad,
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
  expect(match?.wayId, eastWestRoad.id);
});

test('sem rumo rejeita vias próximas ambíguas', () {
  final match = RoadMatcher().select(
    sample: sample(heading: null, headingAccuracy: null),
    candidates: const [
      eastWestRoad,
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
```

- [ ] **Step 2: Run the matcher tests and verify failure**

Run:

```powershell
flutter test test/road_matcher_test.dart
```

Expected: the realistic-offset, reverse, curve, speed-uncertainty and
distance-only tests fail under the existing score.

- [ ] **Step 3: Implement local-segment scoring**

Replace first-to-last geometry scoring with a `_RoadGeometry` calculated from
the nearest segment. The selection algorithm must:

```dart
if (sample.horizontalAccuracy > 20) return null;

final hasReliableHeading =
    sample.heading != null && (sample.headingAccuracy ?? 999) <= 20;
final scored = <_ScoredRoad>[];

for (final road in candidates) {
  if (road.points.length < 2) continue;
  final geometry = _nearestGeometry(sample, road.points);
  final oneway = road.tags['oneway'];
  final directionDifference = hasReliableHeading
      ? _roadDirectionDifference(
          sample.heading!,
          geometry.heading,
          oneway,
        )
      : null;
  if (directionDifference == double.infinity) continue;

  if (hasReliableHeading) {
    if (geometry.distance > 25 || directionDifference! > 90) continue;
    final score = 60 * (1 - geometry.distance / 25) +
        30 * (1 - directionDifference / 90) +
        (previousWayId == road.id ? 10 : 0);
    final minimum = previousWayId == road.id ? 35 : 45;
    if (score < minimum) continue;
    scored.add(_ScoredRoad(
      road,
      _limitForDirection(road, sample.heading!),
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

scored.sort((a, b) => b.score.compareTo(a.score));
if (scored.isEmpty) return null;
if (scored.length > 1) {
  final lead = hasReliableHeading
      ? scored.first.score - scored[1].score
      : scored[1].distance - scored.first.distance;
  if (lead < (hasReliableHeading ? 8 : 10)) return null;
}
```

`_nearestGeometry` must call the existing point-to-segment projection for every
pair, retain the shortest distance, and calculate the bearing from that pair.
`_roadDirectionDifference` must return the direct difference for one-way roads,
reject a forbidden direction with `double.infinity`, and otherwise return:

```dart
math.min(
  _angularDifference(vehicleHeading, segmentHeading),
  _angularDifference(vehicleHeading, (segmentHeading + 180) % 360),
);
```

`_undirectedLimit` may return only a generic `maxspeed`; directional values must
remain unavailable until direction is known.

- [ ] **Step 4: Run the matcher tests and verify pass**

Run:

```powershell
flutter test test/road_matcher_test.dart
```

Expected: all matcher tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/domain/telemetry/road_matcher.dart test/road_matcher_test.dart
git commit -m "fix: torna pareamento de via tolerante e bidirecional"
```

### Task 3: Broaden and harden the Overpass provider

**Files:**
- Modify: `lib/data/road_limit/overpass_road_limit_provider.dart`
- Modify: `test/overpass_road_limit_provider_integration_test.dart`

- [ ] **Step 1: Write failing query and failover tests**

Add tests using injected endpoints:

```dart
test('consulta vias mesmo sem maxspeed e envia headers identificáveis',
    () async {
  late http.Request captured;
  final provider = OverpassRoadLimitProvider(
    endpoints: [Uri.parse('https://primary.test/interpreter')],
    client: MockClient((request) async {
      captured = request;
      return http.Response('''
        {"elements":[
          {"id":10,"tags":{"name":"Rua Livre"},"geometry":[
            {"lat":-23.5,"lon":-46.6},
            {"lat":-23.5,"lon":-46.59}
          ]}
        ]}
      ''', 200);
    }),
  );

  final roads =
      await provider.fetchCandidates(latitude: -23.5, longitude: -46.6);
  final query = Uri.splitQueryString(captured.body)['data']!;

  expect(query, contains('around:40'));
  expect(query, isNot(contains('[maxspeed]')));
  expect(captured.headers['accept'], 'application/json');
  expect(captured.headers['user-agent'], startsWith('speedometer/'));
  expect(roads.single.tags['name'], 'Rua Livre');
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

test('resposta vazia válida não é tratada como falha', () async {
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
```

- [ ] **Step 2: Run provider tests and verify failure**

Run:

```powershell
flutter test test/overpass_road_limit_provider_integration_test.dart
```

Expected: constructor does not accept `endpoints`, the query still filters
`maxspeed`, and failover does not occur.

- [ ] **Step 3: Implement endpoints, headers and per-endpoint circuit state**

Add constructor defaults:

```dart
static final defaultEndpoints = <Uri>[
  Uri.parse('https://overpass-api.de/api/interpreter'),
  Uri.parse('https://maps.mail.ru/osm/tools/overpass/api/interpreter'),
];

OverpassRoadLimitProvider({
  http.Client? client,
  DateTime Function()? clock,
  List<Uri>? endpoints,
})  : _client = client ?? http.Client(),
      _clock = clock ?? DateTime.now,
      _endpoints = List.unmodifiable(endpoints ?? defaultEndpoints);
```

Use this query:

```dart
final query = '''
[out:json][timeout:6];
way(around:40,$latitude,$longitude)
  [highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)\$"];
out tags geom;
''';
```

For each endpoint not currently circuit-open, POST with:

```dart
headers: const {
  'Content-Type': 'application/x-www-form-urlencoded',
  'Accept': 'application/json',
  'User-Agent': 'speedometer/1.0',
},
body: {'data': query},
```

Treat transport errors, timeout, 406, 408, 429 and 5xx as retryable. Increment
failure state only for the endpoint that failed and open its circuit for five
minutes after three failures. Return immediately for a 200 response, including
an empty `elements` list. Throw `RoadDataUnavailable` after all usable
endpoints fail. Keep `_inFlight` coalescing unchanged.

- [ ] **Step 4: Run all provider tests**

Run:

```powershell
flutter test test/overpass_road_limit_provider_test.dart test/overpass_road_limit_provider_integration_test.dart
```

Expected: all provider tests pass, including the adapted circuit test with one
injected endpoint.

- [ ] **Step 5: Commit**

```powershell
git add lib/data/road_limit/overpass_road_limit_provider.dart test/overpass_road_limit_provider_integration_test.dart
git commit -m "fix: amplia consulta e adiciona failover do Overpass"
```

### Task 4: Separate GPS quality states in the controller

**Files:**
- Modify: `lib/presentation/controllers/telemetry_controller.dart`
- Modify: `test/telemetry_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

Add a fake road source that returns a named road with an optional limit, then
cover high speed uncertainty and no limit:

```dart
test('confirma via sem limite e com velocidade imprecisa', () async {
  final location = _FakeLocation();
  final controller = TelemetryController(
    location: location,
    roadLimit: _FakeRoadLimit(limit: null, name: 'Rua sem limite'),
    speech: _FakeSpeech(),
  );

  await controller.start(
    allowOnline: true,
    announceLimits: true,
    announceBands: false,
  );
  final now = DateTime.now();
  location.emit(_validSample(
    timestamp: now,
    speedAccuracy: 4,
    longitude: -46.60000,
  ));
  await Future<void>.delayed(Duration.zero);
  location.emit(_validSample(
    timestamp: now.add(const Duration(seconds: 2)),
    speedAccuracy: 4,
    longitude: -46.59999,
  ));
  await Future<void>.delayed(Duration.zero);

  expect(controller.roadName, 'Rua sem limite');
  expect(controller.roadSpeedLimit, isNull);
  expect(
    controller.degradationReasons,
    contains(TelemetryDegradedReason.speedWeak),
  );
  expect(
    controller.degradationReasons,
    isNot(contains(TelemetryDegradedReason.positionWeak)),
  );
});
```

Add `double speedAccuracy = 1` to `_validSample` and use it in the returned
`TelemetrySample`. Adapt `_FakeRoadLimit`:

```dart
_FakeRoadLimit({this.limit, this.name = 'Via de teste'});
final int? limit;
final String name;
```

and always return tags containing `name`, adding `maxspeed` only when
`limit != null`.

- [ ] **Step 2: Run controller tests and verify failure**

Run:

```powershell
flutter test test/telemetry_controller_test.dart
```

Expected: enum values do not exist, speed uncertainty blocks the lookup, and a
null limit prevents road creation or announcement logic from compiling.

- [ ] **Step 3: Split quality reasons and remove speed accuracy from road matching**

Replace `gpsWeak` with:

```dart
enum TelemetryDegradedReason {
  positionWeak,
  speedWeak,
  locationStale,
  roadMatchLowConfidence,
  overpassUnavailable,
  onlineDataDisabled,
  audioUnavailable,
  ttsUnavailable,
  headingWeak,
  countryBoundaryUncertain,
}
```

In `_onSample`, update states independently:

```dart
if (sample.horizontalAccuracy <= 15) {
  degradationReasons.remove(TelemetryDegradedReason.positionWeak);
} else {
  degradationReasons.add(TelemetryDegradedReason.positionWeak);
}
if (sample.speedAccuracy <= 1.5) {
  degradationReasons.remove(TelemetryDegradedReason.speedWeak);
} else {
  degradationReasons.add(TelemetryDegradedReason.speedWeak);
}
```

Location stream errors and invalid samples add `positionWeak`. In
`_maybeUpdateRoadLimit`, reject only horizontal accuracy above 15 for a new
match; do not test `speedAccuracy`. Do not return early for an unusable heading:
pass the best available sample to the matcher so it can use distance-only
matching.

When the matcher returns null, report `headingWeak` if heading is absent or has
accuracy above 20; otherwise report `roadMatchLowConfidence`. Clear the other
reason in each branch. When a match succeeds, clear both reasons.

Assign all road fields even when the limit is null:

```dart
roadWayId = match.wayId;
lastConfirmedWayId = match.wayId;
roadSpeedLimit = match.limit;
roadName = match.name;
```

Call `_announceRoadLimit` only when `match.limit != null`, and change its
message construction to use the non-null local:

```dart
final limit = match.limit;
if (limit == null) return;
```

- [ ] **Step 4: Run controller tests and verify pass**

Run:

```powershell
flutter test test/telemetry_controller_test.dart
```

Expected: all controller tests pass after updating old `gpsWeak` expectations
to `positionWeak` or `speedWeak` according to their sample.

- [ ] **Step 5: Commit**

```powershell
git add lib/presentation/controllers/telemetry_controller.dart test/telemetry_controller_test.dart
git commit -m "fix: separa qualidade da posição e da velocidade"
```

### Task 5: Show road name without a speed limit

**Files:**
- Modify: `lib/presentation/pages/dashboard_page.dart`
- Modify: `test/limit_status_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add:

```dart
testWidgets('mostra via atual mesmo sem limite', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: LimitStatus(
          isTracking: true,
          roadSpeedLimit: null,
          roadName: 'Rua sem limite',
          degradationReasons: {},
          speedKmh: 30,
        ),
      ),
    ),
  );

  expect(find.text('Limite indisponível'), findsOneWidget);
  expect(find.text('Via atual: Rua sem limite'), findsOneWidget);
  expect(
    find.bySemanticsLabel(
      'Limite indisponível. Via atual: Rua sem limite.',
    ),
    findsOneWidget,
  );
});

testWidgets('distingue posição e velocidade imprecisas', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: LimitStatus(
          isTracking: true,
          roadSpeedLimit: null,
          roadName: null,
          degradationReasons: {
            TelemetryDegradedReason.positionWeak,
            TelemetryDegradedReason.speedWeak,
          },
          speedKmh: 30,
        ),
      ),
    ),
  );

  expect(find.text('Posição GPS com baixa precisão'), findsOneWidget);
  expect(find.text('Velocidade GPS com baixa precisão'), findsOneWidget);
});
```

- [ ] **Step 2: Run widget tests and verify failure**

Run:

```powershell
flutter test test/limit_status_test.dart
```

Expected: semantics omit the road when limit is null and enum labels are not
implemented.

- [ ] **Step 3: Update semantics and labels**

Build the semantic label independently:

```dart
final roadSentence =
    hasRoadName ? ' Via atual: ${roadName!.trim()}.' : '';
final semanticLabel = limit != null
    ? 'Limite: $limit quilômetros por hora.$roadSentence'
    : 'Limite indisponível.$roadSentence';
```

Keep the existing `Via atual` widget controlled only by `hasRoadName`, not by
`limit`. Replace the old switch entry with:

```dart
TelemetryDegradedReason.positionWeak =>
  'Posição GPS com baixa precisão',
TelemetryDegradedReason.speedWeak =>
  'Velocidade GPS com baixa precisão',
```

- [ ] **Step 4: Run widget tests and verify pass**

Run:

```powershell
flutter test test/limit_status_test.dart
```

Expected: all widget tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/presentation/pages/dashboard_page.dart test/limit_status_test.dart
git commit -m "feat: exibe via atual sem limite cadastrado"
```

### Task 6: Verify regressions and integration behavior

**Files:** No source changes are planned in this verification task.

- [ ] **Step 1: Format changed Dart files**

Run:

```powershell
dart format lib/domain/telemetry/telemetry_dependencies.dart lib/domain/telemetry/road_matcher.dart lib/data/road_limit/overpass_road_limit_provider.dart lib/presentation/controllers/telemetry_controller.dart lib/presentation/pages/dashboard_page.dart test/road_matcher_test.dart test/overpass_road_limit_provider_integration_test.dart test/telemetry_controller_test.dart test/limit_status_test.dart
```

Expected: formatter exits with code 0.

- [ ] **Step 2: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run the full unit/widget suite**

Run:

```powershell
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Check patch hygiene**

Run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors; only intentional source and test changes are
listed if the task commits have not already consumed them.

- [ ] **Step 5: Confirm the worktree contains no uncommitted implementation**

Run:

```powershell
git status --short
```

Expected: only the implementation-plan document is untracked or modified; all
source and test changes are already committed by Tasks 1–5.
