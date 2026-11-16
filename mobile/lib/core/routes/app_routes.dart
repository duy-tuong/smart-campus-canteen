import 'package:flutter/material.dart';

import '../../screens/auth/auth_gate.dart';
import '../../screens/auth/forgot_password_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/auth/server_settings_screen.dart';
import '../../models/menu.dart';
import '../../models/order.dart';
import '../../screens/checkout/checkout_screen.dart';
import '../../screens/checkout/order_placed_screen.dart';
import '../../screens/checkout/payment_screen.dart';
import '../../screens/menu/favorites_screen.dart';
import '../../screens/menu/food_detail_screen.dart';
import '../../screens/menu/search_screen.dart';
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
  static const search = '/search';
  static const favorites = '/favorites';

  /// Chi tiết món — arguments: [FoodRouteArgs] (hoặc id món kiểu int).
  static const food = '/food';
  static const checkout = '/checkout';

  /// Thanh toán chuyển khoản (QR) — arguments: [OrderDetail] vừa tạo.
  static const payment = '/payment';

  /// Đặt món thành công — arguments: [OrderDetail].
  static const orderPlaced = '/order-placed';

  static Map<String, WidgetBuilder> get routes => {
    home: (_) => const AuthGate(),
    register: (_) => const RegisterScreen(),
    serverSettings: (_) => const ServerSettingsScreen(),
    search: (_) => const SearchScreen(),
    favorites: (_) => const FavoritesScreen(),
    checkout: (_) => const CheckoutScreen(),
  };

  /// Route có tham số.
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) => switch (settings.name) {
    forgotPassword => MaterialPageRoute(
      settings: settings,
      builder: (_) => ForgotPasswordScreen(initialEmail: settings.arguments as String?),
    ),
    food => MaterialPageRoute(
      settings: settings,
      builder: (_) => switch (settings.arguments) {
        FoodRouteArgs(:final id, :final preview) => FoodDetailScreen(foodId: id, preview: preview),
        int id => FoodDetailScreen(foodId: id),
        _ => throw ArgumentError('Route ${settings.name} cần id món'),
      },
    ),
    payment => MaterialPageRoute(
      settings: settings,
      builder: (_) => PaymentScreen(order: settings.arguments! as OrderDetail),
    ),
    orderPlaced => MaterialPageRoute(
      settings: settings,
      builder: (_) => OrderPlacedScreen(order: settings.arguments! as OrderDetail),
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

/// Tham số mở màn Chi tiết món.
class FoodRouteArgs {
  const FoodRouteArgs(this.id, {this.preview});

  final int id;

  /// Bản tóm tắt từ danh sách — hiện ngay tên/ảnh trong lúc tải chi tiết.
  final FoodSummary? preview;
}
