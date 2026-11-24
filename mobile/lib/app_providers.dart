import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'data/device/image_source_service.dart';
import 'data/firebase/auth_service.dart';
import 'data/firebase/realtime_service.dart';
import 'data/local/cart_dao.dart';
import 'data/local/order_dao.dart';
import 'data/local/search_history_dao.dart';
import 'data/remote/api_client.dart';
import 'data/remote/menu_api.dart';
import 'data/remote/notification_api.dart';
import 'data/remote/order_api.dart';
import 'data/remote/review_api.dart';
import 'data/remote/staff_api.dart';
import 'data/remote/stats_api.dart';
import 'data/remote/user_api.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/home_tabs.dart';
import 'providers/menu_provider.dart';
import 'providers/orders_provider.dart';
import 'providers/settings_provider.dart';

/// Toàn bộ provider của app (dùng chung cho main.dart và test).
///
/// Dữ liệu theo từng người dùng (giỏ hàng, yêu thích) dùng ChangeNotifierProxyProvider:
/// khi AuthProvider đổi người đăng nhập → provider tự xóa dữ liệu cũ / tải dữ liệu mới.
List<SingleChildWidget> buildAppProviders({
  required SettingsProvider settings,
  required ApiClient api,
  required AuthService auth,
  required RealtimeService realtime,
  required ImageSourceService images,
  required CartDao cartDao,
  required OrderDao orderDao,
  SearchHistoryDao? searchHistoryDao,
}) {
  final userApi = UserApi(api);
  final menuApi = MenuApi(api);
  final orderApi = OrderApi(api);

  /// Chỉ coi là "đã đăng nhập" khi đã có hồ sơ (ready) — tránh tải giỏ của phiên chưa hoàn tất.
  String? readyUser(AuthProvider a) => a.status == AuthStatus.ready ? a.user?.uid : null;

  return [
    ChangeNotifierProvider.value(value: settings),
    Provider.value(value: api),
    Provider.value(value: auth),
    Provider.value(value: userApi),
    Provider.value(value: menuApi),
    Provider.value(value: cartDao),
    Provider.value(value: orderDao),
    Provider.value(value: orderApi),
    Provider.value(value: realtime),
    Provider.value(value: images),
    Provider.value(value: ReviewApi(api)),
    Provider.value(value: StaffApi(api)),
    Provider.value(value: StatsApi(api)),
    Provider.value(value: AdminApi(api)),
    Provider.value(value: NotificationApi(api)),
    if (searchHistoryDao != null) Provider.value(value: searchHistoryDao),
    ChangeNotifierProvider(
      create: (_) => AuthProvider(auth: auth, users: userApi, api: api),
      lazy: false, // bắt đầu nghe authStateChanges ngay khi mở app
    ),
    ChangeNotifierProvider(create: (_) => HomeTabs()),
    ChangeNotifierProxyProvider<AuthProvider, MenuProvider>(
      create: (_) => MenuProvider(menuApi),
      update: (_, auth, menu) => menu!..attachUser(readyUser(auth)),
    ),
    ChangeNotifierProxyProvider<AuthProvider, CartProvider>(
      create: (_) => CartProvider(cartDao),
      update: (_, auth, cart) => cart!..attachUser(readyUser(auth)),
    ),
    ChangeNotifierProxyProvider<AuthProvider, OrdersProvider>(
      create: (_) => OrdersProvider(api: orderApi, dao: orderDao, realtime: realtime),
      // Lịch sử đơn + nghe Firebase chỉ dành cho sinh viên (nhân viên có bảng đơn riêng ở F7).
      update: (_, auth, orders) =>
          orders!..attachUser(auth.profile?.role.isStaffOrAdmin ?? true ? null : readyUser(auth)),
    ),
  ];
}
