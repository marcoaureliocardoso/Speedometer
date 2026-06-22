import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/data/heading/android_rotation_vector_heading_data_source.dart';
import 'package:speedometer/domain/telemetry/telemetry_dependencies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('speedometer/rotation_vector_heading/methods');
  const events = MethodChannel('speedometer/rotation_vector_heading/events');

  testWidgets('encaminha a posição para corrigir a declinação magnética',
      (tester) async {
    MethodCall? received;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return call.method == 'isAvailable' ? true : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await AndroidRotationVectorHeadingDataSource().updateLocation(
      TelemetrySample(
        latitude: -23.5,
        longitude: -46.6,
        speedMetersPerSecond: 0,
        speedAccuracy: 1,
      ),
    );

    expect(received?.method, 'setLocation');
    expect(received?.arguments, {'latitude': -23.5, 'longitude': -46.6});
  });

  testWidgets('consulta a disponibilidade do sensor nativo', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(
        await AndroidRotationVectorHeadingDataSource().isAvailable(), isTrue);
  });

  testWidgets('converte o evento nativo de orientação', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(events, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(events, null));
    final heading = Completer<HeadingSensorSample>();
    final subscription = AndroidRotationVectorHeadingDataSource()
        .samples
        .listen(heading.complete);
    addTearDown(subscription.cancel);
    await tester.pump();

    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'degrees': 90.0,
        'accuracy': 3,
      }),
      null,
    );

    final sample = await heading.future;
    expect(sample.degrees, 90);
    expect(sample.accuracy, 3);
  });
}
