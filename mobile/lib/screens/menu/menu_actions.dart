import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes/app_routes.dart';
import '../../models/menu.dart';
import '../../providers/cart_provider.dart';
import '../../providers/home_tabs.dart';
import '../../providers/menu_provider.dart';
import '../../widgets/state_views.dart';

/// Thao tác dùng chung ở lưới thực đơn, tìm kiếm, yêu thích.

/// Mở chi tiết món (truyền kèm bản tóm tắt để hiện ngay tên/ảnh trong lúc tải chi tiết).
Future<void> openFoodDetail(BuildContext context, FoodSummary food) =>
    Navigator.pushNamed(context, AppRoutes.food, arguments: FoodRouteArgs(food.id, preview: food));

/// Bật/tắt yêu thích (cập nhật lạc quan); lỗi → hoàn tác + báo.
Future<void> toggleFavorite(BuildContext context, FoodSummary food) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await context.read<MenuProvider>().toggleFavorite(food);
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(ErrorView.messageOf(e))));
  }
}

/// Nút "+" trên thẻ món: món có tùy chọn → mở chi tiết để chọn; không có → thêm 1 phần ngay.
Future<void> quickAdd(BuildContext context, FoodSummary food) async {
  if (food.hasOptions) return openFoodDetail(context, food);
  final messenger = ScaffoldMessenger.of(context);
  await context.read<CartProvider>().addFood(food);
  if (!context.mounted) return;
  showAddedToCart(context, messenger, food.name);
}

/// SnackBar "Đã thêm vào giỏ" + nút Xem giỏ (chuyển sang tab Giỏ hàng).
void showAddedToCart(BuildContext context, ScaffoldMessengerState messenger, String foodName, {int quantity = 1}) {
  final tabs = context.read<HomeTabs>();
  final navigator = Navigator.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Đã thêm ${quantity > 1 ? '$quantity × ' : ''}$foodName vào giỏ'),
        duration: const Duration(seconds: 3),
        // Flutter mặc định GIỮ SnackBar có nút hành động cho tới khi người dùng đóng (persist = true)
        // → nó che mất nút "Thanh toán". Cho tự ẩn sau [duration].
        persist: false,
        action: SnackBarAction(
          label: 'Xem giỏ',
          onPressed: () {
            navigator.popUntil((r) => r.isFirst);
            tabs.select(HomeTabs.cart);
          },
        ),
      ),
    );
}
