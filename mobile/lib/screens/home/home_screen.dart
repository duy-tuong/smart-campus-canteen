import 'package:flutter/material.dart';

/// Màn hình Home tạm thời (placeholder) để kiểm tra khung project chạy được.
/// Sẽ được thay bằng màn hình thực đơn theo danh mục ở các bước sau.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onToggleTheme});

  /// Callback đổi theme Sáng/Tối (sau này chuyển sang ThemeProvider).
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Canteen'),
        actions: [
          IconButton(
            tooltip: 'Đổi giao diện Sáng/Tối',
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: onToggleTheme,
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu, size: 72),
            SizedBox(height: 16),
            Text('Smart Campus Canteen E-Menu'),
          ],
        ),
      ),
    );
  }
}
