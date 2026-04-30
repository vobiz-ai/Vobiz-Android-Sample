import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'integration/dependency_injection.dart';
import 'presentation/screens/splash_screen.dart';

class VobizDemoApp extends StatelessWidget {
  const VobizDemoApp({super.key});

  static const Color kOrange = Color(0xFFE86A00);
  static const Color kOrangeDark = Color(0xFFE83C00);
  static const Color kBg = Color(0xFF0A0C10);
  static const Color kSurface = Color(0xFF141720);
  static const Color kSurfaceHigh = Color(0xFF1A1D2B);
  static const Color kBorder = Color(0xFF252A3A);
  static const Color kMuted = Color(0xFF8B93A5);
  static const Color kRed = Color(0xFFD92D20);
  static const Color kGreen = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return DependencyInjection(
      child: MaterialApp(
        title: 'Vobiz',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const SplashScreen(),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: kOrange,
        onPrimary: Colors.white,
        secondary: kOrangeDark,
        onSecondary: Colors.white,
        surface: kSurface,
        onSurface: Colors.white,
        surfaceContainerHighest: kSurfaceHigh,
        error: kRed,
        onError: Colors.white,
        outline: kBorder,
        outlineVariant: kBorder,
      ),
      scaffoldBackgroundColor: kBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: kBg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 8,
      ),
      cardTheme: CardThemeData(
        color: kSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kSurfaceHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kOrange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kRed),
        ),
        labelStyle: const TextStyle(color: kMuted),
        hintStyle: const TextStyle(color: kMuted),
        prefixIconColor: kMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kOrange,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: kBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: kOrange),
      ),
      dividerTheme: const DividerThemeData(color: kBorder),
    );
  }
}
