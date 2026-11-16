import '../../data/remote/menu_api.dart';
import '../../models/cart_item.dart';
import '../../models/order.dart';
import '../../providers/cart_provider.dart';

class ReorderResult {
  const ReorderResult({required this.added, required this.skipped});

  /// Số dòng món đã thêm lại vào giỏ.
  final int added;

  /// Tên các món không thêm được (ngừng bán, hết món, tùy chọn không còn).
  final List<String> skipped;
}

/// "Đặt lại": thêm các món của đơn cũ vào giỏ với ĐÚNG tùy chọn đã chọn.
///
/// Hóa đơn chỉ lưu TÊN tùy chọn (bản chụp lúc đặt) → tải thực đơn hiện tại, khớp lại theo
/// (tên nhóm, tên tùy chọn) để lấy id; giá lấy theo thực đơn hiện tại.
Future<ReorderResult> reorder(List<OrderItem> items, {required MenuApi menu, required CartProvider cart}) async {
  var added = 0;
  final skipped = <String>[];
  for (final item in items) {
    final foodId = item.foodId;
    if (foodId == null) {
      skipped.add(item.foodName);
      continue;
    }
    try {
      final food = await menu.food(foodId);
      if (!food.summary.isAvailable || food.summary.isSoldOut) {
        skipped.add(item.foodName);
        continue;
      }
      final options = <CartItemOption>[];
      var allFound = true;
      for (final wanted in item.options) {
        final group = food.optionGroups.where((g) => g.name == wanted.groupName).firstOrNull;
        final option = group?.options.where((o) => o.name == wanted.optionName && o.isAvailable).firstOrNull;
        if (group == null || option == null) {
          allFound = false;
          break;
        }
        options.add(
          CartItemOption(
            optionId: option.id,
            groupName: group.name,
            optionName: option.name,
            extraPrice: option.extraPrice,
          ),
        );
      }
      if (!allFound) {
        skipped.add(item.foodName);
        continue;
      }
      await cart.addFood(food.summary, quantity: item.quantity, options: options, note: item.note);
      added++;
    } catch (_) {
      skipped.add(item.foodName);
    }
  }
  return ReorderResult(added: added, skipped: skipped);
}
