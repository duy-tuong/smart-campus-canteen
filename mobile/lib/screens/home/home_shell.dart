import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/responsive_shell.dart';
import '../../data/firebase/realtime_service.dart';
import '../../models/live.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/home_tabs.dart';
import '../cart/cart_screen.dart';
import '../menu/menu_screen.dart';
import '../notifications/notifications_screen.dart';
import '../orders/orders_screen.dart';
import '../profile/account_screen.dart';

/// Khung chính của sinh viên: 5 tab (Thực đơn, Giỏ hàng, Đơn hàng, Thông báo, Tài khoản).
/// Badge: số phần trong giỏ (SQLite) và số thông báo chưa đọc (StreamBuilder trên Firebase).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final Stream<List<AppNotification>> _notifications;

  @override
  void initState() {
    super.initState();
    context.read<HomeTabs>().reset(); // vào app (đăng nhập mới) → luôn bắt đầu ở tab Thực đơn
    final uid = context.read<AuthProvider>().user!.uid;
    _notifications = context.read<RealtimeService>().watchNotifications(uid);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = context.watch<HomeTabs>();
    final cartCount = context.select<CartProvider, int>((c) => c.totalQuantity);

    return StreamBuilder<List<AppNotification>>(
      stream: _notifications,
      builder: (context, snapshot) {
        final unread = snapshot.data?.where((n) => !n.isRead).length ?? 0;
        return ResponsiveShell(
          destinations: [
            const ShellDestination(
              icon: Icons.restaurant_menu_outlined,
              selectedIcon: Icons.restaurant_menu_rounded,
              label: 'Thực đơn',
            ),
            ShellDestination(
              icon: Icons.shopping_bag_outlined,
              selectedIcon: Icons.shopping_bag_rounded,
              label: 'Giỏ hàng',
              badgeCount: cartCount,
            ),
            const ShellDestination(
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long_rounded,
              label: 'Đơn hàng',
            ),
            ShellDestination(
              icon: Icons.notifications_outlined,
              selectedIcon: Icons.notifications_rounded,
              label: 'Thông báo',
              badgeCount: unread,
            ),
            const ShellDestination(
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: 'Tài khoản',
            ),
          ],
          selectedIndex: tabs.index,
          onDestinationSelected: tabs.select,
          railLeading: Icon(Icons.lunch_dining_rounded, color: Theme.of(context).colorScheme.primary, size: 32),
          pages: const [MenuScreen(), CartScreen(), OrdersScreen(), NotificationsScreen(), AccountScreen()],
        );
      },
    );
  }
}
