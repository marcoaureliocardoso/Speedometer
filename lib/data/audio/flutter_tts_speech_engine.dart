import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/telemetry/telemetry_dependencies.dart';

class FlutterTtsSpeechEngine implements SpeechEngine {
  final _tts = FlutterTts();

  @override
  Future<bool> configure({
    required double volume,
    required double speechRate,
  }) async {
    final available = await _tts.isLanguageAvailable('pt-BR');
    if (available != true) return false;
    await _tts.setLanguage('pt-BR');
    await _tts.awaitSpeakCompletion(true);
    await _tts.setVolume(volume);
    await _tts.setSpeechRate(speechRate);
    return true;
  }

  @override
  Future<void> speak(String message) => _tts.speak(message);

  @override
  Future<void> stop() => _tts.stop();
}
