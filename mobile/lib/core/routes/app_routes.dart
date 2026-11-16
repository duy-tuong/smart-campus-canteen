import 'package:flutter/material.dart';

import '../../screens/auth/auth_gate.dart';
import '../../screens/auth/forgot_password_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/auth/server_settings_screen.dart';
import '../../widgets/state_views.dart';

/// Tên route và bảng điều hướng của app.
///
///  - Màn không cần tham số → khai báo trong [routes], mở bằng `Navigator.pushNamed(context, AppRoutes.x)`.
///  - Màn cần tham số → xử lý trong [onGenerateRoute],
///    mở bằng `Navigator.pushNamed(context, AppRoutes.forgotPassword, arguments: email)`.
abstract final class AppRoutes {
  /// Gốc: AuthGate chọn Đăng nhập / Hoàn tất hồ sơ / khung Sinh viên / khung Nhân viên.
  static const home = '/';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const serverSettings = '/settings/server';

  static Map<String, WidgetBuilder> get routes => {
        home: (_) => const AuthGate(),
        register: (_) => const RegisterScreen(),
        serverSettings: (_) => const ServerSettingsScreen(),
      };

  /// Route có tham số.
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) => switch (settings.name) {
        forgotPassword => MaterialPageRoute(
            settings: settings,
            builder: (_) => ForgotPasswordScreen(initialEmail: settings.arguments as String?),
          ),
        _ => null,
      };

  /// Route không tồn tại → màn báo lỗi thay vì crash.
  static Route<dynamic> onUnknownRoute(RouteSettings settings) => MaterialPageRoute(
        settings: settings,
        builder: (context) => Scaffold(
          appBar: AppBar(),
          body: EmptyState(
            icon: Icons.explore_off_outlined,
            title: 'Không tìm thấy trang',
            message: 'Đường dẫn "${settings.name}" không tồn tại.',
            actionLabel: 'Về trang chủ',
            onAction: () => Navigator.of(context).pushNamedAndRemoveUntil(home, (_) => false),
          ),
        ),
      );
}
