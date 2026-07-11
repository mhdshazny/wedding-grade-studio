import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(WeddingGradeApp(state: AppState()));
}

class WeddingGradeApp extends StatelessWidget {
  final AppState state;
  const WeddingGradeApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    const champagne = Color(0xFFD7B98A);
    final scheme = ColorScheme.fromSeed(
      seedColor: champagne,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Wedding Grade Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF141110),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141110),
          surfaceTintColor: Colors.transparent,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: scheme.primary,
          inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.15),
        ),
      ),
      home: HomeScreen(state: state),
    );
  }
}
