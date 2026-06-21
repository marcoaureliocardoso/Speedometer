import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/telemetry/telemetry_dependencies.dart';

class FlutterTtsSpeechEngine implements SpeechEngine {
  final _tts = FlutterTts();

  @override
  Future<bool> configure({
    required double volume,
    required double speechRate,
  }) async {
    try {
      final available = await _tts
          .isLanguageAvailable('pt-BR')
          .timeout(const Duration(seconds: 3));
      if (available != true) return false;
      await _tts.setLanguage('pt-BR').timeout(const Duration(seconds: 3));
      await _tts.awaitSpeakCompletion(true).timeout(const Duration(seconds: 3));
      await _tts.setVolume(volume).timeout(const Duration(seconds: 3));
      await _tts.setSpeechRate(speechRate).timeout(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> speak(String message) => _tts.speak(message);

  @override
  Future<void> stop() => _tts.stop();
}
