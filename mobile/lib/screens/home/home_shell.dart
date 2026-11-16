import 'package:flutter/material.dart';

import '../../core/responsive/responsive_shell.dart';
import '../../widgets/state_views.dart';
import '../profile/account_screen.dart';

/// Khung chính của sinh viên: 5 tab.
/// Các tab được thay bằng màn thật ở F3–F6; tab Tài khoản dùng chung với khung nhân viên.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    ShellDestination(icon: Icons.restaurant_menu_outlined, selectedIcon: Icons.restaurant_menu_rounded, label: 'Thực đơn'),
    ShellDestination(icon: Icons.shopping_bag_outlined, selectedIcon: Icons.shopping_bag_rounded, label: 'Giỏ hàng'),
    ShellDestination(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long_rounded, label: 'Đơn hàng'),
    ShellDestination(icon: Icons.notifications_outlined, selectedIcon: Icons.notifications_rounded, label: 'Thông báo'),
    ShellDestination(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'Tài khoản'),
  ];

  @override
  Widget build(BuildContext context) {
    return ResponsiveShell(
      destinations: _destinations,
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      railLeading: Icon(Icons.lunch_dining_rounded, color: Theme.of(context).colorScheme.primary, size: 32),
      pages: const [
        _ComingSoon(title: 'Thực đơn', icon: Icons.restaurant_menu_rounded, message: 'Lưới món, tìm kiếm và lọc theo danh mục.'),
        _ComingSoon(title: 'Giỏ hàng', icon: Icons.shopping_bag_rounded, message: 'Giỏ hàng lưu trên máy, đặt món và thanh toán.'),
        _ComingSoon(title: 'Đơn hàng', icon: Icons.receipt_long_rounded, message: 'Theo dõi đơn realtime và lịch sử đơn offline.'),
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
