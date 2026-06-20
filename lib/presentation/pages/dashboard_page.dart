import 'package:flutter/material.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('0', style: TextStyle(fontSize: 96, fontWeight: FontWeight.bold)),
              Text('km/h'),
              SizedBox(height: 16),
              Text('Limite indisponível'),
            ],
          ),
        ),
      ),
    );
  }
}
