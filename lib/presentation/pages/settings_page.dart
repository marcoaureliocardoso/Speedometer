import 'package:flutter/material.dart';

enum VoiceMode { silent, limitsOnly, limitsAndBands }

extension VoiceModeLabel on VoiceMode {
  String get label => switch (this) {
        VoiceMode.silent => 'Silencioso',
        VoiceMode.limitsOnly => 'Limites apenas',
        VoiceMode.limitsAndBands => 'Limites e faixas',
      };
}

class VoiceSettings {
  const VoiceSettings({
    this.mode = VoiceMode.limitsOnly,
    this.volume = 1,
    this.speechRate = 1,
  });

  final VoiceMode mode;
  final double volume;
  final double speechRate;

  VoiceSettings copyWith(
      {VoiceMode? mode, double? volume, double? speechRate}) {
    return VoiceSettings(
      mode: mode ?? this.mode,
      volume: volume ?? this.volume,
      speechRate: speechRate ?? this.speechRate,
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settings,
    required this.onChanged,
    super.key,
  });

  final VoiceSettings settings;
  final ValueChanged<VoiceSettings> onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late VoiceSettings _settings = widget.settings;

  void _update(VoiceSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Alertas de voz', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('As alterações se aplicam ao próximo alerta de voz.'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modo de voz',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  RadioGroup<VoiceMode>(
                    groupValue: _settings.mode,
                    onChanged: (mode) =>
                        _update(_settings.copyWith(mode: mode)),
                    child: const Column(
                      children: [
                        RadioListTile<VoiceMode>(
                          contentPadding: EdgeInsets.zero,
                          value: VoiceMode.silent,
                          title: Text('Silencioso'),
                        ),
                        RadioListTile<VoiceMode>(
                          contentPadding: EdgeInsets.zero,
                          value: VoiceMode.limitsOnly,
                          title: Text('Limites apenas'),
                        ),
                        RadioListTile<VoiceMode>(
                          contentPadding: EdgeInsets.zero,
                          value: VoiceMode.limitsAndBands,
                          title: Text('Limites e faixas de 5 km/h'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SliderSetting(
                    label: 'Volume relativo',
                    value: _settings.volume,
                    min: 0,
                    max: 1,
                    divisions: 20,
                    valueLabel: '${(_settings.volume * 100).round()}%',
                    onChanged: (value) =>
                        _update(_settings.copyWith(volume: value)),
                  ),
                  const SizedBox(height: 16),
                  _SliderSetting(
                    label: 'Velocidade de fala',
                    value: _settings.speechRate,
                    min: .5,
                    max: 1.5,
                    divisions: 10,
                    valueLabel: '${_settings.speechRate.toStringAsFixed(1)}×',
                    onChanged: (value) =>
                        _update(_settings.copyWith(speechRate: value)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SettingsHint(
            icon: Icons.volume_up_outlined,
            title: 'Exemplo de voz',
            body:
                'Disponível quando o motor de voz pt-BR estiver configurado no dispositivo.',
          ),
        ],
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $valueLabel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text(valueLabel)],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsHint extends StatelessWidget {
  const _SettingsHint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
