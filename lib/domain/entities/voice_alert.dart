enum VoiceAlertKind { speedBand, belowHalfLimit, aboveLimit }

class VoiceAlert {
  const VoiceAlert({required this.kind, required this.message});

  final VoiceAlertKind kind;
  final String message;
}
