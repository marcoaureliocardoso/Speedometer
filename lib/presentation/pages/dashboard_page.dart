import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/preferences/app_preferences.dart';
import '../../data/audio/flutter_tts_speech_engine.dart';
import '../controllers/telemetry_controller.dart';
import 'offline_regions_page.dart';
import 'settings_page.dart';
import '../widgets/speedometer_gauge.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _telemetry = TelemetryController();
  final _preferences = AppPreferences();
  String? _dataMode;
  VoiceSettings _voiceSettings = const VoiceSettings();

  bool get _isTracking => _telemetry.isTracking;

  @override
  void initState() {
    super.initState();
    _telemetry.addListener(_onTelemetryChanged);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final saved = await _preferences.load();
    if (!mounted) return;
    setState(() {
      _dataMode = saved.dataMode;
      _voiceSettings = VoiceSettings(
        mode: VoiceMode.values[saved.voiceModeIndex.clamp(0, VoiceMode.values.length - 1)],
        volume: saved.volume,
        speechRate: saved.speechRate,
      );
    });
  }

  Future<void> _savePreferences() => _preferences.save(
        voiceModeIndex: _voiceSettings.mode.index,
        volume: _voiceSettings.volume,
        speechRate: _voiceSettings.speechRate,
        dataMode: _dataMode,
      );

  void _onTelemetryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _telemetry
      ..removeListener(_onTelemetryChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _startTracking() async {
    String? selectedMode = _dataMode;
    selectedMode ??= await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => const _DataModeSheet(initialMode: 'Somente offline'),
      );

    if (selectedMode != null && mounted) {
      setState(() => _dataMode = selectedMode);
      await _savePreferences();
      await _telemetry.start(
        allowOnline: selectedMode == 'Online e offline',
        announceLimits: _voiceSettings.mode != VoiceMode.silent,
        announceBands: _voiceSettings.mode == VoiceMode.limitsAndBands,
        volume: _voiceSettings.volume,
        speechRate: _voiceSettings.speechRate,
      );
    }
  }

  Future<void> _stopTracking() async {
    await _telemetry.stop();
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
          dataMode: _dataMode ?? 'Somente offline',
          onChanged: (settings) {
            setState(() => _voiceSettings = settings);
            _savePreferences();
          },
          onDataModeChanged: (dataMode) {
            setState(() => _dataMode = dataMode);
            _savePreferences();
          },
          onPreview: _playVoicePreview,
        ),
      ),
    );
  }

  Future<void> _playVoicePreview(VoiceSettings settings) async {
    if (settings.mode == VoiceMode.silent) return;
    final speech = FlutterTtsSpeechEngine();
    if (await speech.configure(volume: settings.volume, speechRate: settings.speechRate)) {
      await speech.speak('Exemplo de alerta de velocidade.');
    }
  }

  Future<void> _openCurrentWayInOsm() async {
    final wayId = _telemetry.lastConfirmedWayId;
    if (wayId == null) return;
    await launchUrl(Uri.parse('https://www.openstreetmap.org/way/$wayId'),
        mode: LaunchMode.externalApplication);
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
                  if (_telemetry.status == TrackingStatus.permissionDenied ||
                      _telemetry.status == TrackingStatus.permissionDeniedForever ||
                      _telemetry.status == TrackingStatus.locationDisabled) ...[
                    const SizedBox(height: 8),
                    _TrackingAvailabilityNotice(
                      status: _telemetry.status,
                      onRetry: _startTracking,
                      onOpenSettings: _telemetry.status == TrackingStatus.locationDisabled
                          ? _telemetry.openLocationSettings
                          : _telemetry.openAppSettings,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: isLandscape
                        ? _LandscapeDashboard(
                            isTracking: _isTracking,
                            speedKmh: _telemetry.speedKmh,
                            filteredNeedleSpeed: _telemetry.filteredNeedleSpeed,
                            roadSpeedLimit: _telemetry.roadSpeedLimit,
                            status: _telemetry.status,
                            degradationReasons: _telemetry.degradationReasons,
                          )
                        : _PortraitDashboard(
                            isTracking: _isTracking,
                            speedKmh: _telemetry.speedKmh,
                            filteredNeedleSpeed: _telemetry.filteredNeedleSpeed,
                            roadSpeedLimit: _telemetry.roadSpeedLimit,
                            status: _telemetry.status,
                            degradationReasons: _telemetry.degradationReasons,
                          ),
                  ),
                  const SizedBox(height: 16),
                  if (!_isTracking && _telemetry.lastConfirmedWayId != null)
                    TextButton.icon(
                      onPressed: _openCurrentWayInOsm,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir via atual no OpenStreetMap'),
                    ),
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

class _TrackingAvailabilityNotice extends StatelessWidget {
  const _TrackingAvailabilityNotice({
    required this.status,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final TrackingStatus status;
  final Future<void> Function() onRetry;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final permanentlyDenied = status == TrackingStatus.permissionDeniedForever;
    final serviceDisabled = status == TrackingStatus.locationDisabled;
    final message = serviceDisabled
        ? 'A localização está desativada. Ative-a para iniciar o rastreamento.'
        : permanentlyDenied
            ? 'A permissão de localização foi negada permanentemente.'
            : 'A localização precisa é necessária para medir a velocidade.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (!permanentlyDenied && !serviceDisabled)
                  TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
                if (permanentlyDenied || serviceDisabled)
                  TextButton(
                    onPressed: onOpenSettings,
                    child: Text(serviceDisabled ? 'Abrir configurações de localização' : 'Abrir configurações do Android'),
                  ),
              ],
            ),
          ],
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
  const _PortraitDashboard(
      {required this.isTracking,
      required this.speedKmh,
      required this.filteredNeedleSpeed,
      required this.status,
      required this.degradationReasons,
      required this.roadSpeedLimit});

  final bool isTracking;
  final double? speedKmh;
  final double? filteredNeedleSpeed;
  final TrackingStatus status;
  final Set<TelemetryDegradedReason> degradationReasons;
  final int? roadSpeedLimit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _SpeedReadout(isTracking: isTracking, status: status, speedKmh: speedKmh),
          const SizedBox(height: 16),
          SpeedometerGauge(speed: filteredNeedleSpeed, roadSpeedLimit: roadSpeedLimit?.toDouble()),
          const SizedBox(height: 16),
          _LimitStatus(isTracking: isTracking, roadSpeedLimit: roadSpeedLimit, degradationReasons: degradationReasons, speedKmh: speedKmh),
          const SizedBox(height: 16),
          const _LegalNotice(),
        ],
      ),
    );
  }
}

class _LandscapeDashboard extends StatelessWidget {
  const _LandscapeDashboard(
      {required this.isTracking,
      required this.speedKmh,
      required this.filteredNeedleSpeed,
      required this.status,
      required this.degradationReasons,
      required this.roadSpeedLimit});

  final bool isTracking;
  final double? speedKmh;
  final double? filteredNeedleSpeed;
  final TrackingStatus status;
  final Set<TelemetryDegradedReason> degradationReasons;
  final int? roadSpeedLimit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _SpeedReadout(isTracking: isTracking, status: status, speedKmh: speedKmh),
              Expanded(
                child: Center(
                  child: SpeedometerGauge(
                      speed: filteredNeedleSpeed,
                      roadSpeedLimit: roadSpeedLimit?.toDouble()),
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
                _LimitStatus(
                    isTracking: isTracking, roadSpeedLimit: roadSpeedLimit, degradationReasons: degradationReasons, speedKmh: speedKmh),
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
  const _SpeedReadout({required this.isTracking, required this.status, required this.speedKmh});

  final bool isTracking;
  final TrackingStatus status;
  final double? speedKmh;

  @override
  Widget build(BuildContext context) {
    final speed = speedKmh?.round().toString() ?? (isTracking ? '—' : '0');
    final label = speedKmh == null
        ? (isTracking
            ? 'Aguardando uma posição válida do GPS'
            : 'Velocidade atual: 0 quilômetros por hora')
        : 'Velocidade atual: $speed quilômetros por hora';
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
            if (status == TrackingStatus.awaitingGps) ...[
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
  const _LimitStatus({required this.isTracking, required this.roadSpeedLimit, required this.degradationReasons, required this.speedKmh});

  final bool isTracking;
  final int? roadSpeedLimit;
  final Set<TelemetryDegradedReason> degradationReasons;
  final double? speedKmh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final limit = roadSpeedLimit;
    final isOverLimit = limit != null && (speedKmh ?? 0) > limit;
    return Semantics(
      label: limit != null
          ? 'Limite: $limit quilômetros por hora.'
          : isTracking
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
                      Text(
                          limit != null
                              ? 'Limite: $limit km/h'
                              : 'Limite indisponível',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      if (isOverLimit)
                        const Row(children: [Icon(Icons.warning_amber_rounded), SizedBox(width: 6), Text('Acima do limite')]),
                      if (degradationReasons.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _DegradationSummary(reasons: degradationReasons),
                      ],
                      Text(
                        limit != null
                            ? 'OSM online · Sinalização oficial prevalece.'
                            : isTracking
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

class _DegradationSummary extends StatelessWidget {
  const _DegradationSummary({required this.reasons});
  final Set<TelemetryDegradedReason> reasons;
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 6,
        children: reasons.map((reason) => Chip(label: Text(switch (reason) {
          TelemetryDegradedReason.gpsWeak => 'GPS com baixa precisão',
          TelemetryDegradedReason.locationStale => 'Localização desatualizada',
          TelemetryDegradedReason.roadMatchLowConfidence => 'Via não confirmada',
          TelemetryDegradedReason.overpassUnavailable => 'Consulta online indisponível',
          TelemetryDegradedReason.onlineDataDisabled => 'Modo somente offline',
          TelemetryDegradedReason.audioUnavailable => 'Áudio indisponível',
          TelemetryDegradedReason.ttsUnavailable => 'Voz pt-BR indisponível',
          TelemetryDegradedReason.countryBoundaryUncertain => 'Limite indisponível perto da fronteira',
        }))).toList(),
      );
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
