import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/responsive_shell.dart';
import '../../models/enums.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/state_views.dart';
import '../profile/account_screen.dart';

/// Khung của Nhân viên căn-tin / Quản trị viên. Admin có thêm tab Người dùng.
/// Nội dung các tab được làm ở F7 (bảng đơn, thực đơn) và F8 (thống kê, người dùng).
class StaffShell extends StatefulWidget {
  const StaffShell({super.key});

  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<AuthProvider, bool>((a) => a.profile?.role == UserRole.admin);

    final tabs = <(ShellDestination, Widget)>[
      (
        const ShellDestination(
          icon: Icons.view_kanban_outlined,
          selectedIcon: Icons.view_kanban_rounded,
          label: 'Bảng đơn',
        ),
        const _ComingSoon(
          'Bảng đơn',
          Icons.view_kanban_rounded,
          'Đơn mới hiện ngay theo thời gian thực, chuyển bước bằng một chạm.',
        ),
      ),
      (
        const ShellDestination(
          icon: Icons.menu_book_outlined,
          selectedIcon: Icons.menu_book_rounded,
          label: 'Thực đơn',
        ),
        const _ComingSoon(
          'Quản lý thực đơn',
          Icons.menu_book_rounded,
          'Thêm, sửa món, tùy chọn, ảnh và số suất mỗi ngày.',
        ),
      ),
      (
        const ShellDestination(icon: Icons.insights_outlined, selectedIcon: Icons.insights_rounded, label: 'Thống kê'),
        const _ComingSoon('Thống kê', Icons.insights_rounded, 'Doanh thu, món bán chạy và giờ cao điểm.'),
      ),
      if (isAdmin)
        (
          const ShellDestination(icon: Icons.group_outlined, selectedIcon: Icons.group_rounded, label: 'Người dùng'),
          const _ComingSoon('Người dùng', Icons.group_rounded, 'Tìm kiếm, đổi vai trò, khóa / mở khóa tài khoản.'),
        ),
      (
        const ShellDestination(
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          label: 'Tài khoản',
        ),
        const AccountScreen(),
      ),
    ];
    final index = _index.clamp(0, tabs.length - 1);

    return ResponsiveShell(
      destinations: [for (final t in tabs) t.$1],
      pages: [for (final t in tabs) t.$2],
      selectedIndex: index,
      onDestinationSelected: (i) => setState(() => _index = i),
      railLeading: Icon(Icons.storefront_rounded, color: Theme.of(context).colorScheme.primary, size: 32),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon(this.title, this.icon, this.message);

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: EmptyState(icon: icon, title: 'Sắp ra mắt', message: message),
  );
}
