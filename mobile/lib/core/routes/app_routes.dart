import 'package:flutter/material.dart';

import '../../screens/auth/server_settings_screen.dart';
import '../../screens/home/home_shell.dart';
import '../../widgets/state_views.dart';

/// Tên route và bảng điều hướng của app.
///
///  - Màn không cần tham số → khai báo trong [routes], mở bằng `Navigator.pushNamed(context, AppRoutes.x)`.
///  - Màn cần tham số (chi tiết món, chi tiết đơn...) → xử lý trong [onGenerateRoute],
///    mở bằng `Navigator.pushNamed(context, AppRoutes.food, arguments: foodId)`.
abstract final class AppRoutes {
  static const home = '/';
  static const serverSettings = '/settings/server';

  static Map<String, WidgetBuilder> get routes => {
        home: (_) => const HomeShell(),
        serverSettings: (_) => const ServerSettingsScreen(),
      };

  /// Route có tham số (bổ sung ở các phần sau: /food, /order...).
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) => switch (settings.name) {
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
