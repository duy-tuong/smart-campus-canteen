import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/responsive/responsive_shell.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/enums.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

/// Khung chính của sinh viên (tạm thời ở F1): 5 tab với nội dung giữ chỗ.
/// Các tab được thay bằng màn thật ở F3–F6; tab Tài khoản đã có chọn giao diện và cài đặt máy chủ.
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
        _AccountTab(),
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

class _AccountTab extends StatelessWidget {
  const _AccountTab();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          MaxWidthBox(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionHeader('Giao diện'),
              Padding(
                padding: AppSpacing.pagePadding,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Sáng')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Tối')),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Hệ thống')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => settings.setThemeMode(s.first),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Kết nối'),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Địa chỉ máy chủ'),
                subtitle: Text(settings.apiBaseUrl),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(context, AppRoutes.serverSettings),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Bộ nhận diện'),
              Padding(
                padding: AppSpacing.pagePadding,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
                        for (final s in OrderStatus.values) StatusChip(s),
                      ]),
                      const SizedBox(height: AppSpacing.md),
                      Row(children: [
                        const AppNetworkImage(null, width: 64, height: 64, borderRadius: AppRadius.mdAll),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Cơm gà xối mỡ', style: theme.textTheme.titleSmall),
                            const SizedBox(height: AppSpacing.xxs),
                            const PriceText(35000, originalAmount: 40000),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(onPressed: () {}, child: const Text('Thêm vào giỏ')),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
