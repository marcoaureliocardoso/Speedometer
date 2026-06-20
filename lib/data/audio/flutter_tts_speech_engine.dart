import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/telemetry/telemetry_dependencies.dart';

class FlutterTtsSpeechEngine implements SpeechEngine {
  final _tts = FlutterTts();

  @override
  Future<void> configure() async {
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(1);
  }

  @override
  Future<void> speak(String message) => _tts.speak(message);

  @override
  Future<void> stop() => _tts.stop();
}
