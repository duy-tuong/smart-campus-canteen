import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'providers/settings_provider.dart';

/// Widget gốc: MaterialApp với theme Sáng/Tối (theo [SettingsProvider]), tiếng Việt và điều hướng có tên.
/// Các provider (Settings, ApiClient, DAO...) được cung cấp từ main.dart.
class CanteenApp extends StatelessWidget {
  const CanteenApp({super.key, this.initialRoute = AppRoutes.home});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<SettingsProvider, ThemeMode>((s) => s.themeMode);

    return MaterialApp(
      title: 'Smart Canteen',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      initialRoute: initialRoute,
      routes: AppRoutes.routes,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      onUnknownRoute: AppRoutes.onUnknownRoute,
      // Giới hạn cỡ chữ hệ thống quá lớn để bố cục không vỡ (vẫn tôn trọng tùy chỉnh trợ năng tới 1.3×).
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: media.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3)),
          child: child!,
        );
      },
    );
  }
}
