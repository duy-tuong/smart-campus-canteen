import 'package:flutter/material.dart';

/// Bảng màu của app — quy tắc 60/30/10:
///  - 60% nền trung tính ẤM (trắng kem / gần đen) để món ăn nổi bật,
///  - 30% chữ và khối tối,
///  - 10% CAM thương hiệu chỉ cho nút chính và chỉ báo quan trọng.
/// Màu đỏ để dành cho "Đã hủy" và lỗi — dùng nhiều sẽ mất ý nghĩa cảnh báo.
abstract final class AppPalette {
  /// Cam thương hiệu (gợi cảm giác đồ ăn, ấm áp, thúc đẩy hành động).
  static const Color brand = Color(0xFFF57C00);

  static const Color lightBackground = Color(0xFFFFFBF7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightInk = Color(0xFF1F1A17);

  static const Color darkBackground = Color(0xFF14110F);
  static const Color darkSurface = Color(0xFF1E1A17);
  static const Color darkInk = Color(0xFFF5EFEA);
}

/// Màu ngữ nghĩa bổ sung cho ColorScheme của Material 3 (trạng thái đơn, giá, đánh giá...).
/// Truy cập: `context.appColors.cooking`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.received,
    required this.cooking,
    required this.ready,
    required this.completed,
    required this.cancelled,
    required this.success,
    required this.warning,
    required this.rating,
    required this.price,
    required this.shadow,
    required this.subtleBrand,
  });

  /// Đã nhận — xanh dương: bình tĩnh, "đã ghi nhận".
  final Color received;

  /// Đang nấu — hổ phách: đang diễn ra, cần chờ.
  final Color cooking;

  /// Mời nhận món — xanh lá: hành động ngay, khoảnh khắc đáng nhớ nhất của hành trình.
  final Color ready;

  /// Hoàn thành — xám xanh: đã kết thúc, không cần chú ý.
  final Color completed;

  /// Đã hủy — đỏ.
  final Color cancelled;

  final Color success;
  final Color warning;

  /// Màu sao đánh giá.
  final Color rating;

  /// Màu giá tiền (đậm, dễ đọc).
  final Color price;

  /// Bóng đổ ngả theo màu nền (không dùng đen thuần).
  final Color shadow;

  /// Cam rất nhạt (~6%) cho nền chip/nút phụ/thẻ được chọn.
  final Color subtleBrand;

  static const AppColors light = AppColors(
    received: Color(0xFF2563EB),
    cooking: Color(0xFFD97706),
    ready: Color(0xFF16A34A),
    completed: Color(0xFF64748B),
    cancelled: Color(0xFFDC2626),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    rating: Color(0xFFF5A623),
    price: Color(0xFFC2410C),
    shadow: Color(0x1A7C2D12),
    subtleBrand: Color(0x0FF57C00),
  );

  static const AppColors dark = AppColors(
    received: Color(0xFF60A5FA),
    cooking: Color(0xFFFBBF24),
    ready: Color(0xFF4ADE80),
    completed: Color(0xFF94A3B8),
    cancelled: Color(0xFFF87171),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    rating: Color(0xFFFBBF24),
    price: Color(0xFFFDBA74),
    shadow: Color(0x66000000),
    subtleBrand: Color(0x1FF57C00),
  );

  @override
  AppColors copyWith({
    Color? received,
    Color? cooking,
    Color? ready,
    Color? completed,
    Color? cancelled,
    Color? success,
    Color? warning,
    Color? rating,
    Color? price,
    Color? shadow,
    Color? subtleBrand,
  }) =>
      AppColors(
        received: received ?? this.received,
        cooking: cooking ?? this.cooking,
        ready: ready ?? this.ready,
        completed: completed ?? this.completed,
        cancelled: cancelled ?? this.cancelled,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        rating: rating ?? this.rating,
        price: price ?? this.price,
        shadow: shadow ?? this.shadow,
        subtleBrand: subtleBrand ?? this.subtleBrand,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      received: Color.lerp(received, other.received, t)!,
      cooking: Color.lerp(cooking, other.cooking, t)!,
      ready: Color.lerp(ready, other.ready, t)!,
      completed: Color.lerp(completed, other.completed, t)!,
      cancelled: Color.lerp(cancelled, other.cancelled, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      rating: Color.lerp(rating, other.rating, t)!,
      price: Color.lerp(price, other.price, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      subtleBrand: Color.lerp(subtleBrand, other.subtleBrand, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
