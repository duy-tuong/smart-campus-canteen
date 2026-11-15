import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/home/home_screen.dart';

/// Widget gốc của ứng dụng: cấu hình MaterialApp, theme Sáng/Tối và điều hướng.
///
/// Hiện tại giữ trạng thái theme bằng StatefulWidget; sẽ chuyển sang
/// ThemeProvider + AuthGate (authStateChanges) khi tích hợp Provider/Firebase.
class CanteenApp extends StatefulWidget {
  const CanteenApp({super.key});

  @override
  State<CanteenApp> createState() => _CanteenAppState();
}

class _CanteenAppState extends State<CanteenApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Canteen',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: HomeScreen(onToggleTheme: _toggleTheme),
    );
  }
}
