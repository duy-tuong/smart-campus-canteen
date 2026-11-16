import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'data/firebase/auth_service.dart';
import 'data/local/cart_dao.dart';
import 'data/local/order_dao.dart';
import 'data/local/search_history_dao.dart';
import 'data/remote/api_client.dart';
import 'data/remote/menu_api.dart';
import 'data/remote/user_api.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/home_tabs.dart';
import 'providers/menu_provider.dart';
import 'providers/settings_provider.dart';

/// Toàn bộ provider của app (dùng chung cho main.dart và test).
///
/// Dữ liệu theo từng người dùng (giỏ hàng, yêu thích) dùng ChangeNotifierProxyProvider:
/// khi AuthProvider đổi người đăng nhập → provider tự xóa dữ liệu cũ / tải dữ liệu mới.
List<SingleChildWidget> buildAppProviders({
  required SettingsProvider settings,
  required ApiClient api,
  required AuthService auth,
  required CartDao cartDao,
  OrderDao? orderDao,
  SearchHistoryDao? searchHistoryDao,
}) {
  final userApi = UserApi(api);
  final menuApi = MenuApi(api);

  /// Chỉ coi là "đã đăng nhập" khi đã có hồ sơ (ready) — tránh tải giỏ của phiên chưa hoàn tất.
  String? readyUser(AuthProvider a) => a.status == AuthStatus.ready ? a.user?.uid : null;

  return [
    ChangeNotifierProvider.value(value: settings),
    Provider.value(value: api),
    Provider.value(value: auth),
    Provider.value(value: userApi),
    Provider.value(value: menuApi),
    Provider.value(value: cartDao),
    if (orderDao != null) Provider.value(value: orderDao),
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
  ];
}
