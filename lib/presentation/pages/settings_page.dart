import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _unchanged = Object();

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
    this.bandIntervalKmh = 5,
    this.customSpeedLimitKmh,
  }) : assert(bandIntervalKmh == 5 || bandIntervalKmh == 10);

  final VoiceMode mode;
  final double volume;
  final double speechRate;
  final int bandIntervalKmh;
  final int? customSpeedLimitKmh;

  VoiceSettings copyWith({
    VoiceMode? mode,
    double? volume,
    double? speechRate,
    int? bandIntervalKmh,
    Object? customSpeedLimitKmh = _unchanged,
  }) {
    return VoiceSettings(
      mode: mode ?? this.mode,
      volume: volume ?? this.volume,
      speechRate: speechRate ?? this.speechRate,
      bandIntervalKmh: bandIntervalKmh ?? this.bandIntervalKmh,
      customSpeedLimitKmh: identical(customSpeedLimitKmh, _unchanged)
          ? this.customSpeedLimitKmh
          : customSpeedLimitKmh as int?,
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settings,
    required this.dataMode,
    required this.onChanged,
    required this.onDataModeChanged,
    required this.onPreview,
    super.key,
  });

  final VoiceSettings settings;
  final String dataMode;
  final ValueChanged<VoiceSettings> onChanged;
  final ValueChanged<String> onDataModeChanged;
  final Future<void> Function(VoiceSettings settings) onPreview;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late VoiceSettings _settings = widget.settings;
  late String _dataMode = widget.dataMode;
  late final TextEditingController _customLimitController =
      TextEditingController(
          text: _settings.customSpeedLimitKmh?.toString() ?? '');
  String? _customLimitError;

  void _update(VoiceSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  void _updateCustomSpeedLimit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _customLimitError = null);
      _update(_settings.copyWith(customSpeedLimitKmh: null));
      return;
    }
    final limit = int.tryParse(trimmed);
    if (limit == null || limit < 1 || limit > 300) {
      setState(
          () => _customLimitError = 'Informe um valor entre 1 e 300 km/h.');
      return;
    }
    setState(() => _customLimitError = null);
    _update(_settings.copyWith(customSpeedLimitKmh: limit));
  }

  @override
  void dispose() {
    _customLimitController.dispose();
    super.dispose();
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
                  if (_settings.mode == VoiceMode.limitsAndBands) ...[
                    const SizedBox(height: 16),
                    Text('Intervalo da narração',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text(
                        'Escolha a frequência dos avisos de velocidade atual.'),
                    RadioGroup<int>(
                      groupValue: _settings.bandIntervalKmh,
                      onChanged: (interval) {
                        if (interval != null) {
                          _update(
                              _settings.copyWith(bandIntervalKmh: interval));
                        }
                      },
                      child: Column(
                        children: [
                          RadioListTile<int>(
                            contentPadding: EdgeInsets.zero,
                            value: 5,
                            selected: _settings.bandIntervalKmh == 5,
                            title: Text('A cada 5 km/h'),
                          ),
                          RadioListTile<int>(
                            contentPadding: EdgeInsets.zero,
                            value: 10,
                            selected: _settings.bandIntervalKmh == 10,
                            title: Text('A cada 10 km/h'),
                          ),
                        ],
                      ),
                    ),
                  ],
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Limite de velocidade personalizado',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text(
                    'Opcional. Ao ultrapassá-lo, o app avisa por voz.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customLimitController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: _updateCustomSpeedLimit,
                    decoration: InputDecoration(
                      labelText: 'Limite personalizado (km/h)',
                      hintText: 'Ex.: 80',
                      errorText: _customLimitError,
                      suffixIcon: _settings.customSpeedLimitKmh != null
                          ? IconButton(
                              tooltip: 'Remover limite personalizado',
                              onPressed: () {
                                _customLimitController.clear();
                                _updateCustomSpeedLimit('');
                              },
                              icon: const Icon(Icons.clear),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modo de dados',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                      'O modo online envia a posição atual diretamente ao Overpass/OSM para identificar a via.'),
                  RadioGroup<String>(
                    groupValue: _dataMode,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _dataMode = value);
                        widget.onDataModeChanged(value);
                      }
                    },
                    child: const Column(children: [
                      RadioListTile<String>(
                          value: 'Online e offline',
                          title: Text('Online e offline')),
                      RadioListTile<String>(
                          value: 'Somente offline',
                          title: Text('Somente offline')),
                    ]),
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => widget.onPreview(_settings),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Ouvir exemplo'),
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
