import 'package:flutter/material.dart';

class OfflineRegionsPage extends StatelessWidget {
  const OfflineRegionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Regiões offline')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma região offline',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Prepare regiões locais para consultar limites mesmo sem conexão. A seleção e a construção serão disponibilizadas quando a base offline estiver configurada.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => _showOfflineSetupInfo(context),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Como preparar uma região'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOfflineSetupInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Regiões offline'),
            SizedBox(height: 12),
            Text(
              'Você poderá escolher um ponto, definir o raio, revisar área, espaço e tempo estimados e confirmar o envio da área ao Overpass.',
            ),
          ],
        ),
      ),
    );
  }
}
