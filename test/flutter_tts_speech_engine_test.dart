import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/data/audio/flutter_tts_speech_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('configura a voz pt-BR quando disponível', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    final configured = await FlutterTtsSpeechEngine().configure(
      volume: .65,
      speechRate: 1.2,
    );

    expect(configured, isTrue);
    expect(
      calls.map((call) => call.method),
      [
        'isLanguageAvailable',
        'setLanguage',
        'awaitSpeakCompletion',
        'setVolume',
        'setSpeechRate',
      ],
    );
  });

  test('não habilita a voz quando pt-BR não está disponível', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return false;
    });

    final configured = await FlutterTtsSpeechEngine().configure(
      volume: 1,
      speechRate: 1,
    );

    expect(configured, isFalse);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'isLanguageAvailable');
  });

  test('trata falhas da plataforma como voz indisponível', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });

    final configured = await FlutterTtsSpeechEngine().configure(
      volume: 1,
      speechRate: 1,
    );

    expect(configured, isFalse);
  });

  test('encaminha fala e interrupção ao canal de plataforma', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final engine = FlutterTtsSpeechEngine();

    await engine.speak('Teste de voz');
    await engine.stop();

    expect(calls.map((call) => call.method), ['speak', 'stop']);
  });
}
