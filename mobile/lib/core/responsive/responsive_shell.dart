import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'breakpoints.dart';

/// Một mục trên thanh điều hướng chính.
class ShellDestination {
  const ShellDestination({required this.icon, required this.selectedIcon, required this.label, this.badgeCount = 0});

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// > 0 thì hiện chấm số (giỏ hàng, thông báo chưa đọc).
  final int badgeCount;
}

/// Khung điều hướng thích ứng theo bề rộng (LayoutBuilder):
///  - compact  (< 600):  NavigationBar ở dưới — nằm trong vùng ngón cái.
///  - medium   (600–1023): NavigationRail thu gọn bên trái.
///  - expanded (≥ 1024): NavigationRail mở rộng có nhãn.
///
/// Nội dung các tab giữ nguyên trạng thái khi chuyển tab (IndexedStack).
class ResponsiveShell extends StatelessWidget {
  const ResponsiveShell({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.pages,
    this.railLeading,
  }) : assert(destinations.length == pages.length);

  final List<ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> pages;

  /// Logo/nút đặt ở đầu NavigationRail (chỉ hiện trên màn rộng).
  final Widget? railLeading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = ScreenSize.fromWidth(constraints.maxWidth);
        final body = IndexedStack(index: selectedIndex, children: pages);

        if (size.isCompact) {
          return Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: _withBadge(d.icon, d.badgeCount),
                    selectedIcon: _withBadge(d.selectedIcon, d.badgeCount),
                    label: d.label,
                  ),
              ],
            ),
          );
        }

        final extended = size.isExpanded;
        return Scaffold(
          body: SafeArea(
            right: false,
            child: Row(
              children: [
                _ScrollableRail(
                  child: NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    extended: extended,
                    minExtendedWidth: 220,
                    labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                    leading: railLeading == null
                        ? null
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                            child: railLeading,
                          ),
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: _withBadge(d.icon, d.badgeCount),
                          selectedIcon: _withBadge(d.selectedIcon, d.badgeCount),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _withBadge(IconData icon, int count) =>
      count <= 0 ? Icon(icon) : Badge(label: Text(count > 99 ? '99+' : '$count'), child: Icon(icon));
}

/// Điện thoại xoay ngang chỉ cao ~360dp — không đủ chỗ cho 5 mục có nhãn.
/// Cho rail cuộn dọc khi thiếu chỗ; đủ chỗ thì vẫn chiếm hết chiều cao như bình thường.
class _ScrollableRail extends StatelessWidget {
  const _ScrollableRail({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(child: child),
      ),
    ),
  );
}
