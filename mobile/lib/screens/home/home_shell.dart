import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../core/responsive/responsive_shell.dart';
import '../../providers/cart_provider.dart';
import '../../providers/home_tabs.dart';
import '../../widgets/state_views.dart';
import '../cart/cart_screen.dart';
import '../menu/menu_screen.dart';
import '../profile/account_screen.dart';

/// Khung chính của sinh viên: 5 tab.
/// Các tab được thay bằng màn thật ở F3–F6; tab Tài khoản dùng chung với khung nhân viên.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    context.read<HomeTabs>().reset(); // vào app (đăng nhập mới) → luôn bắt đầu ở tab Thực đơn
  }

  @override
  Widget build(BuildContext context) {
    final tabs = context.watch<HomeTabs>();
    final cartCount = context.select<CartProvider, int>((c) => c.totalQuantity);

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
        const ShellDestination(
          icon: Icons.notifications_outlined,
          selectedIcon: Icons.notifications_rounded,
          label: 'Thông báo',
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
      pages: const [
        MenuScreen(),
        CartScreen(),
        _ComingSoon(
          title: 'Đơn hàng',
          icon: Icons.receipt_long_rounded,
          message: 'Theo dõi đơn realtime và lịch sử đơn offline.',
        ),
        _ComingSoon(title: 'Thông báo', icon: Icons.notifications_rounded, message: 'Thông báo khi món sẵn sàng.'),
        AccountScreen(),
      ],
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.icon, required this.message});

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: EmptyState(icon: icon, title: 'Sắp ra mắt', message: message),
  );
}
