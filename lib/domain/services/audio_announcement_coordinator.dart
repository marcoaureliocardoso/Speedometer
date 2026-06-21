import '../entities/voice_alert.dart';
import '../telemetry/telemetry_dependencies.dart';

/// Mantém no máximo uma fala em curso e descarta alertas que ficariam velhos.
class AudioAnnouncementCoordinator {
  int? _activePriority;

  Future<bool> announce(VoiceAlert alert, SpeechEngine speech) async {
    final active = _activePriority;
    if (active != null && alert.priority >= active) return false;
    if (active != null) await speech.stop();
    _activePriority = alert.priority;
    try {
      await speech.speak(alert.message);
      return true;
    } finally {
      _activePriority = null;
    }
  }

  Future<void> stop(SpeechEngine speech) async {
    _activePriority = null;
    await speech.stop();
  }
}
