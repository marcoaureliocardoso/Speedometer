import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:speedometer/domain/entities/voice_alert.dart';
import 'package:speedometer/domain/services/audio_announcement_coordinator.dart';
import 'package:speedometer/domain/telemetry/telemetry_dependencies.dart';

void main() {
  test('descarta faixa enquanto alerta de prioridade maior está ativo', () async {
    final speech = _FakeSpeech(holdFirstMessage: true);
    final coordinator = AudioAnnouncementCoordinator();
    final high = coordinator.announce(
      const VoiceAlert(kind: VoiceAlertKind.aboveLimit, message: 'Acima'),
      speech,
    );
    await Future<void>.delayed(Duration.zero);

    final accepted = await coordinator.announce(
      const VoiceAlert(kind: VoiceAlertKind.speedBand, message: 'Faixa'),
      speech,
    );
    expect(accepted, isFalse);
    expect(speech.messages, ['Acima']);
    speech.releaseFirst();
    await high;
  });

  test('excesso interrompe alerta de prioridade menor sem criar fila', () async {
    final speech = _FakeSpeech(holdFirstMessage: true);
    final coordinator = AudioAnnouncementCoordinator();
    final low = coordinator.announce(
      const VoiceAlert(kind: VoiceAlertKind.belowHalfLimit, message: 'Baixa'),
      speech,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      await coordinator.announce(
        const VoiceAlert(kind: VoiceAlertKind.aboveLimit, message: 'Acima'),
        speech,
      ),
      isTrue,
    );
    expect(speech.stops, 1);
    expect(speech.messages, ['Baixa', 'Acima']);
    speech.releaseFirst();
    await low;
  });
}

class _FakeSpeech implements SpeechEngine {
  _FakeSpeech({required this.holdFirstMessage});
  final bool holdFirstMessage;
  final List<String> messages = [];
  final _firstDone = Completer<void>();
  int stops = 0;

  @override
  Future<bool> configure({required double volume, required double speechRate}) async => true;
  @override
  Future<void> speak(String message) {
    messages.add(message);
    return holdFirstMessage && messages.length == 1 ? _firstDone.future : Future.value();
  }
  @override
  Future<void> stop() async => stops++;
  void releaseFirst() => _firstDone.complete();
}
