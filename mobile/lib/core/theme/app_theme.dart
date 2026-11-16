import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

/// ThemeData Sáng/Tối của toàn app (Material 3).
///
/// Typography: MỘT họ chữ (Roboto — hiển thị tốt tiếng Việt), tối đa 4 cỡ và 2 độ đậm:
///   24 (tiêu đề màn) · 18 (tiêu đề nhóm, giá lớn) · 14 (nội dung) · 12 (chú thích)
///   độ đậm 400 (thường) và 600 (nhấn mạnh).
/// Phân cấp chữ phụ bằng ĐỘ MỜ của màu chữ (onSurfaceVariant) thay vì thêm cỡ/độ đậm.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final ink = isDark ? AppPalette.darkInk : AppPalette.lightInk;
    final background = isDark ? AppPalette.darkBackground : AppPalette.lightBackground;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final extra = isDark ? AppColors.dark : AppColors.light;

    final scheme = ColorScheme.fromSeed(seedColor: AppPalette.brand, brightness: brightness).copyWith(
      primary: AppPalette.brand,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: ink.withValues(alpha: 0.68),
      outlineVariant: ink.withValues(alpha: 0.10),
      error: extra.cancelled,
    );

    final text = _textTheme(ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: text,
      extensions: [extra],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(kMinTapTarget * 2, kMinTapTarget + 4),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(kMinTapTarget * 2, kMinTapTarget + 4),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          side: BorderSide(color: AppPalette.brand.withValues(alpha: 0.4)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(kMinTapTarget, kMinTapTarget), textStyle: text.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFFFF6EE),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: const OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: AppPalette.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: extra.cancelled),
        ),
        hintStyle: text.bodyMedium?.copyWith(color: ink.withValues(alpha: 0.45)),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: surface,
        selectedColor: AppPalette.brand.withValues(alpha: isDark ? 0.24 : 0.12),
        labelStyle: text.bodyMedium,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: AppPalette.brand.withValues(alpha: isDark ? 0.24 : 0.14),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.bodySmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: AppPalette.brand.withValues(alpha: isDark ? 0.24 : 0.14),
        selectedLabelTextStyle: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: ink),
        unselectedLabelTextStyle: text.bodySmall?.copyWith(color: ink.withValues(alpha: 0.68)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        backgroundColor: isDark ? AppPalette.lightSurface : AppPalette.lightInk,
        contentTextStyle: text.bodyMedium?.copyWith(color: isDark ? AppPalette.lightInk : Colors.white),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minVerticalPadding: AppSpacing.sm,
        iconColor: ink.withValues(alpha: 0.68),
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(color: ink.withValues(alpha: 0.68)),
      ),
    );
  }

  /// 4 cỡ chữ (24/18/14/12) × 2 độ đậm (400/600).
  static TextTheme _textTheme(Color ink) {
    TextStyle style(double size, FontWeight weight, {double height = 1.4}) =>
        TextStyle(fontSize: size, fontWeight: weight, height: height, color: ink, letterSpacing: 0);

    final title = style(24, FontWeight.w600, height: 1.25);
    final section = style(18, FontWeight.w600, height: 1.3);
    final body = style(14, FontWeight.w400);
    final bodyStrong = style(14, FontWeight.w600);
    final caption = style(12, FontWeight.w400);

    return TextTheme(
      displaySmall: title,
      headlineMedium: title,
      headlineSmall: title,
      titleLarge: title,
      titleMedium: section,
      titleSmall: bodyStrong,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: bodyStrong,
      labelMedium: caption.copyWith(fontWeight: FontWeight.w600),
      labelSmall: caption,
    );
  }
}

/// Kiểu chữ cho CON SỐ (giá, mã nhận món, thống kê): chữ số đều độ rộng → các cột số thẳng hàng,
/// số không "nhảy" khi đếm ngược/cập nhật.
extension NumericText on TextStyle {
  TextStyle get tabular => copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
