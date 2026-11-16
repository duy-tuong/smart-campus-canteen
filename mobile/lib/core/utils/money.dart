import 'package:intl/intl.dart';

/// Định dạng tiền Việt Nam: 8000 → "8.000đ". Không phụ thuộc ngôn ngữ của máy.
abstract final class Money {
  static final NumberFormat _format = NumberFormat.decimalPattern('vi_VN');

  static String format(num amount) => '${_format.format(amount)}đ';

  /// Có dấu: "+5.000đ" (giá cộng thêm của tùy chọn), "−5.000đ" (giảm giá).
  static String signed(num amount) {
    if (amount == 0) return format(0);
    return amount > 0 ? '+${format(amount)}' : '−${format(-amount)}';
  }

  /// Rút gọn cho trục biểu đồ / thẻ thống kê: 36.821.300 → "36,8tr", 56.000 → "56k".
  static String compact(num amount) {
    final abs = amount.abs();
    final sign = amount < 0 ? '−' : '';
    if (abs >= 1e9) return '$sign${_trim(abs / 1e9)}tỷ';
    if (abs >= 1e6) return '$sign${_trim(abs / 1e6)}tr';
    if (abs >= 1e3) return '$sign${_trim(abs / 1e3)}k';
    return '$sign${abs.toInt()}';
  }

  static String _trim(double value) {
    final text = value.toStringAsFixed(value >= 100 ? 0 : 1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text.replaceAll('.', ',');
  }
}
