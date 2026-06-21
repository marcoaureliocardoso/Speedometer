enum VoiceAlertKind { roadLimitChanged, speedBand, belowHalfLimit, aboveLimit }

class VoiceAlert {
  const VoiceAlert({required this.kind, required this.message});

  final VoiceAlertKind kind;
  final String message;

  int get priority => switch (kind) {
        VoiceAlertKind.roadLimitChanged => 1,
        VoiceAlertKind.aboveLimit => 2,
        VoiceAlertKind.belowHalfLimit => 3,
        VoiceAlertKind.speedBand => 4,
      };
}
