import 'package:flutter/material.dart';

import 'offline_regions_page.dart';
import 'settings_page.dart';
import '../widgets/speedometer_gauge.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isTracking = false;
  String _dataMode = 'Somente offline';
  VoiceSettings _voiceSettings = const VoiceSettings();

  Future<void> _startTracking() async {
    final selectedMode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _DataModeSheet(initialMode: _dataMode),
    );

    if (selectedMode != null && mounted) {
      setState(() {
        _dataMode = selectedMode;
        _isTracking = true;
      });
    }
  }

  void _stopTracking() {
    setState(() => _isTracking = false);
  }

  void _showInformation() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sobre os limites',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(
              'Os limites usam dados do OpenStreetMap quando houver fonte confiável. '
              'A sinalização oficial da via sempre prevalece.',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: _voiceSettings,
          onChanged: (settings) => setState(() => _voiceSettings = settings),
        ),
      ),
    );
  }

  Future<void> _openOfflineRegions() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const OfflineRegionsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = constraints.maxWidth > constraints.maxHeight;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _DashboardHeader(
                    isTracking: _isTracking,
                    onInformation: _showInformation,
                    onSettings: _openSettings,
                    onOfflineRegions: _openOfflineRegions,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: isLandscape
                        ? _LandscapeDashboard(isTracking: _isTracking)
                        : _PortraitDashboard(isTracking: _isTracking),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    button: true,
                    label: _isTracking
                        ? 'Encerrar rastreamento'
                        : 'Iniciar rastreamento',
                    child: FilledButton.icon(
                      onPressed: _isTracking ? _stopTracking : _startTracking,
                      icon: Icon(_isTracking
                          ? Icons.stop_circle_outlined
                          : Icons.play_arrow),
                      label: Text(
                        _isTracking
                            ? 'Encerrar rastreamento'
                            : 'Iniciar rastreamento',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.isTracking,
    required this.onInformation,
    required this.onSettings,
    required this.onOfflineRegions,
  });

  final bool isTracking;
  final VoidCallback onInformation;
  final VoidCallback onSettings;
  final VoidCallback onOfflineRegions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = isTracking ? 'Rastreamento ativo' : 'Rastreamento parado';
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: label,
            child: ExcludeSemantics(
              child: Chip(
                avatar: Icon(
                  isTracking
                      ? Icons.location_searching
                      : Icons.location_disabled,
                  size: 18,
                ),
                label: Text(label),
                backgroundColor: colorScheme.surface,
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Informações sobre os limites',
          onPressed: onInformation,
          icon: const Icon(Icons.info_outline),
        ),
        if (!isTracking)
          IconButton(
            tooltip: 'Regiões offline',
            onPressed: onOfflineRegions,
            icon: const Icon(Icons.map_outlined),
          ),
        if (!isTracking)
          IconButton(
            tooltip: 'Configurações',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
      ],
    );
  }
}

class _PortraitDashboard extends StatelessWidget {
  const _PortraitDashboard({required this.isTracking});

  final bool isTracking;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _SpeedReadout(isTracking: isTracking),
          const SizedBox(height: 16),
          const SpeedometerGauge(speed: null, roadSpeedLimit: null),
          const SizedBox(height: 16),
          _LimitStatus(isTracking: isTracking),
          const SizedBox(height: 16),
          const _LegalNotice(),
        ],
      ),
    );
  }
}

class _LandscapeDashboard extends StatelessWidget {
  const _LandscapeDashboard({required this.isTracking});

  final bool isTracking;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _SpeedReadout(isTracking: isTracking),
              const Expanded(
                child: Center(
                  child: SpeedometerGauge(speed: null, roadSpeedLimit: null),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LimitStatus(isTracking: isTracking),
                const SizedBox(height: 16),
                const _LegalNotice(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({required this.isTracking});

  final bool isTracking;

  @override
  Widget build(BuildContext context) {
    final speed = isTracking ? '—' : '0';
    final label = isTracking
        ? 'Aguardando uma posição válida do GPS'
        : 'Velocidade atual: 0 quilômetros por hora';
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child:
                  Text(speed, style: Theme.of(context).textTheme.headlineLarge),
            ),
            Text('km/h', style: Theme.of(context).textTheme.titleMedium),
            if (isTracking) ...[
              const SizedBox(height: 4),
              const Text('Aguardando GPS'),
            ],
          ],
        ),
      ),
    );
  }
}

class _LimitStatus extends StatelessWidget {
  const _LimitStatus({required this.isTracking});

  final bool isTracking;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: isTracking
          ? 'Limite indisponível. Aguardando uma posição válida.'
          : 'Limite indisponível.',
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.speed_outlined, color: colorScheme.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Limite indisponível',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        isTracking
                            ? 'Aguardando GPS e confirmação da via.'
                            : 'Inicie o rastreamento para consultar o limite da via.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalNotice extends StatelessWidget {
  const _LegalNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'A sinalização oficial da via prevalece.',
      child: const Text(
        'A sinalização oficial da via prevalece.',
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _DataModeSheet extends StatefulWidget {
  const _DataModeSheet({required this.initialMode});

  final String initialMode;

  @override
  State<_DataModeSheet> createState() => _DataModeSheetState();
}

class _DataModeSheetState extends State<_DataModeSheet> {
  late String _selectedMode = widget.initialMode;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Modo de dados',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'No modo online, sua posição atual é enviada diretamente à API pública do OSM/Overpass para identificar a via.',
              ),
              const SizedBox(height: 16),
              RadioGroup<String>(
                groupValue: _selectedMode,
                onChanged: (value) => setState(() => _selectedMode = value!),
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'Online e offline',
                      title: Text('Online e offline'),
                      subtitle: Text(
                          'Consulta limites online e usa dados locais quando disponíveis.'),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'Somente offline',
                      title: Text('Somente offline'),
                      subtitle: Text(
                          'Não envia sua posição para consulta de limites.'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _selectedMode),
                child: const Text('Continuar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
