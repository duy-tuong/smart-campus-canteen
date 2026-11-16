import 'package:flutter/widgets.dart';

/// Ba cỡ màn hình theo Material 3 (đo bằng bề rộng khả dụng, không phải kích thước thiết bị).
enum ScreenSize {
  /// < 600: điện thoại dọc — thanh điều hướng dưới, 1 cột.
  compact,

  /// 600–1023: điện thoại ngang, máy tính bảng nhỏ — NavigationRail.
  medium,

  /// ≥ 1024: máy tính bảng ngang, desktop — NavigationRail mở rộng, bố cục 2 cột.
  expanded;

  static ScreenSize fromWidth(double width) => width < Breakpoints.medium
      ? compact
      : width < Breakpoints.expanded
          ? medium
          : expanded;

  /// Đọc từ MediaQuery (cả màn hình). Trong một vùng con, dùng LayoutBuilder + [fromWidth].
  static ScreenSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == compact;
  bool get isExpanded => this == expanded;
}

abstract final class Breakpoints {
  static const double medium = 600;
  static const double expanded = 1024;

  /// Nội dung dạng chữ không nên rộng hơn mức này (dễ đọc trên máy tính bảng).
  static const double maxContentWidth = 720;

  /// Số cột lưới món theo bề rộng vùng chứa: 2 / 3 / 4 / 5.
  static int gridColumns(double width) => switch (width) {
        < 600 => 2,
        < 900 => 3,
        < 1200 => 4,
        _ => 5,
      };
}

/// Giới hạn bề rộng nội dung và căn giữa — form, cài đặt, chi tiết trên màn rộng.
class MaxWidthBox extends StatelessWidget {
  const MaxWidthBox({super.key, required this.child, this.maxWidth = Breakpoints.maxContentWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
