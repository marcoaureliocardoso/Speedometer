import 'package:flutter/material.dart';

import '../presentation/pages/dashboard_page.dart';

abstract final class AppTheme {
  static const _darkBackground = Color(0xFF0B1015);
  static const _darkSurface = Color(0xFF17212B);
  static const _lightBackground = Color(0xFFF7F9FC);
  static const _lightSurface = Color(0xFFFFFFFF);

  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: _lightBackground,
        surface: _lightSurface,
        onSurface: const Color(0xFF18212B),
        primary: const Color(0xFF006782),
        onPrimary: Colors.white,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: _darkBackground,
        surface: _darkSurface,
        onSurface: const Color(0xFFF1F5F9),
        primary: const Color(0xFF75D5F7),
        onPrimary: const Color(0xFF003546),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color onSurface,
    required Color primary,
    required Color onPrimary,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: const Color(0xFFFFD166),
      onSecondary: const Color(0xFF332600),
      error: const Color(0xFFFF6B6B),
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 112,
          fontWeight: FontWeight.w800,
          letterSpacing: -2,
          color: onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: onSurface),
        bodyMedium: TextStyle(fontSize: 14, color: onSurface),
      ),
    );
  }
}

class SpeedometerApp extends StatelessWidget {
  const SpeedometerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speedometer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const DashboardPage(),
    );
  }
}
