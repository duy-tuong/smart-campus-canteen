import 'package:flutter/widgets.dart';

/// Khoảng cách theo lưới 8 điểm (mọi giá trị chia hết cho 4 hoặc 8).
///
/// Quy tắc dùng: phần tử liên quan đặt gần nhau ([sm]/[md]); giữa các nhóm khác nhau
/// dùng khoảng gấp đôi ([lg]/[xl]) để mắt tự nhóm thông tin.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Lề ngang của nội dung trang trên điện thoại.
  static const double page = 16;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: page);
}

/// Bo góc: nhỏ cho chip/ô nhập, vừa cho nút, lớn cho thẻ, rất lớn cho bottom sheet.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

/// Thời lượng chuyển động (micro-animation ngắn, không gây chờ).
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}

/// Kích thước tối thiểu của vùng chạm (≥ 48dp theo Material, ≥ 44pt theo Apple).
const double kMinTapTarget = 48;
