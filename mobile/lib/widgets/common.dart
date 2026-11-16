import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/money.dart';
import '../models/enums.dart';

/// Chip trạng thái đơn — mỗi trạng thái một màu ngữ nghĩa (nền nhạt 12%, chữ đậm).
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final OrderStatus status;

  static Color colorOf(BuildContext context, OrderStatus status) {
    final c = context.appColors;
    return switch (status) {
      OrderStatus.received => c.received,
      OrderStatus.cooking => c.cooking,
      OrderStatus.ready => c.ready,
      OrderStatus.completed => c.completed,
      OrderStatus.cancelled => c.cancelled,
    };
  }

  static IconData iconOf(OrderStatus status) => switch (status) {
    OrderStatus.received => Icons.receipt_long_rounded,
    OrderStatus.cooking => Icons.local_fire_department_rounded,
    OrderStatus.ready => Icons.notifications_active_rounded,
    OrderStatus.completed => Icons.check_circle_rounded,
    OrderStatus.cancelled => Icons.cancel_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.smAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconOf(status), size: 14, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Giá tiền: chữ số đều nhau (tabular), màu giá; có thể kèm giá gốc gạch ngang.
class PriceText extends StatelessWidget {
  const PriceText(this.amount, {super.key, this.style, this.originalAmount, this.color});

  final int amount;
  final int? originalAmount;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = (style ?? theme.textTheme.titleSmall ?? const TextStyle()).tabular;
    final main = Text(
      Money.format(amount),
      style: base.copyWith(color: color ?? context.appColors.price, fontWeight: FontWeight.w600),
    );
    if (originalAmount == null || originalAmount! <= amount) return main;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        main,
        const SizedBox(width: AppSpacing.xs),
        Text(
          Money.format(originalAmount!),
          style: theme.textTheme.bodySmall?.tabular.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
  }
}

/// Tiêu đề một nhóm nội dung + nút "Xem tất cả" tùy chọn.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.padding = AppSpacing.pagePadding});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    ),
  );
}

/// Ảnh từ mạng có cache; không có ảnh / lỗi tải → ô nền cam nhạt với biểu tượng món ăn.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.icon = Icons.restaurant_rounded,
  });

  final String? url;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(icon: icon, width: width, height: height);
    final image = url == null || url!.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            width: width,
            height: height,
            fit: fit,
            fadeInDuration: AppDurations.normal,
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
    return borderRadius == null ? image : ClipRRect(borderRadius: borderRadius!, child: image);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, this.width, this.height});

  final IconData icon;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    color: context.appColors.subtleBrand,
    alignment: Alignment.center,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final size = side.isFinite ? (side * 0.4).clamp(16.0, 56.0) : 32.0;
        return Icon(icon, size: size, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5));
      },
    ),
  );
}
