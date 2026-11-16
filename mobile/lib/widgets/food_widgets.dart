import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../models/menu.dart';
import 'common.dart';

/// Biểu tượng danh mục: backend lưu tên Material Icon ("rice_bowl") → IconData.
IconData categoryIcon(String name) => switch (name) {
  'rice_bowl' => Icons.rice_bowl_rounded,
  'ramen_dining' => Icons.ramen_dining_rounded,
  'local_drink' => Icons.local_drink_rounded,
  'local_cafe' || 'coffee' => Icons.local_cafe_rounded,
  'bakery_dining' => Icons.bakery_dining_rounded,
  'icecream' => Icons.icecream_rounded,
  'cake' => Icons.cake_rounded,
  'fastfood' => Icons.fastfood_rounded,
  'lunch_dining' => Icons.lunch_dining_rounded,
  'set_meal' => Icons.set_meal_rounded,
  'soup_kitchen' => Icons.soup_kitchen_rounded,
  'emoji_food_beverage' => Icons.emoji_food_beverage_rounded,
  'local_pizza' => Icons.local_pizza_rounded,
  'egg' => Icons.egg_rounded,
  _ => Icons.restaurant_rounded,
};

/// Hàng sao (hỗ trợ nửa sao) — dùng cho điểm trung bình.
class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.size = 16});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.rating;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : rating >= i - 0.5
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded,
            size: size,
            color: color,
          ),
      ],
    );
  }
}

/// "★ 4.2 (27)" gọn cho thẻ món. Chưa có đánh giá → "Món mới".
class RatingLabel extends StatelessWidget {
  const RatingLabel({super.key, required this.average, required this.count});

  final double average;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (count == 0) return Text('Món mới', style: muted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 16, color: context.appColors.rating),
        const SizedBox(width: 2),
        Text(
          average.toStringAsFixed(1),
          style: theme.textTheme.bodySmall?.tabular.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(' ($count)', style: muted?.tabular),
      ],
    );
  }
}

/// Nút − số lượng + (giới hạn [min]–[max]).
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 50,
    this.compact = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = compact ? 36.0 : kMinTapTarget;
    Widget button(IconData icon, String tooltip, int? next) => SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: compact ? 18 : 22,
        onPressed: next == null ? null : () => onChanged(next),
        icon: Icon(icon),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.remove_rounded, 'Giảm', value > min ? value - 1 : null),
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: compact ? 24 : 32),
            child: Text('$value', textAlign: TextAlign.center, style: theme.textTheme.titleSmall?.tabular),
          ),
          button(Icons.add_rounded, 'Tăng', value < max ? value + 1 : null),
        ],
      ),
    );
  }
}

/// Nút tim yêu thích tròn, nền mờ — đặt trên ảnh món.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.isFavorite, required this.onPressed, this.size = 36});

  final bool isFavorite;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Tooltip(
          message: isFavorite ? 'Bỏ yêu thích' : 'Yêu thích',
          child: SizedBox.square(
            dimension: size,
            child: AnimatedSwitcher(
              duration: AppDurations.fast,
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Icon(
                isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(isFavorite),
                size: size * 0.55,
                color: isFavorite ? context.appColors.cancelled : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thẻ món trong lưới thực đơn.
///
/// Ảnh (tỉ lệ 4:3) · tim yêu thích · nhãn "Hết món"/"Còn N suất" · tên · sao · giá · nút thêm nhanh.
class FoodCard extends StatelessWidget {
  const FoodCard({
    super.key,
    required this.food,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
    required this.onAdd,
    this.quantityInCart = 0,
  });

  final FoodSummary food;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  /// Thêm nhanh (món không có tùy chọn) hoặc mở chi tiết để chọn tùy chọn.
  final VoidCallback onAdd;
  final int quantityInCart;

  /// Tỉ lệ khung ảnh.
  static const imageAspect = 4 / 3;

  /// Chiều cao phần chữ dưới ảnh (ở cỡ chữ chuẩn) — lưới dùng để tính chiều cao ô:
  /// lề 8 + tên 2 dòng 39 + 4 + dòng sao 17 + nút 48 + lề 8 ≈ 124 (+4 dư).
  static const infoHeight = 128.0;

  bool get _orderable => food.isAvailable && !food.isSoldOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final remaining = food.remainingToday;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: imageAspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(tag: 'food-image-${food.id}', child: AppNetworkImage(food.imageUrl)),
                  if (!_orderable)
                    Container(
                      color: theme.colorScheme.surface.withValues(alpha: 0.6),
                      alignment: Alignment.center,
                      child: _Badge(
                        text: food.isSoldOut ? 'Hết món hôm nay' : 'Tạm ngưng bán',
                        color: colors.cancelled,
                      ),
                    ),
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: FavoriteButton(isFavorite: isFavorite, onPressed: onFavorite),
                  ),
                  if (_orderable && remaining != null && remaining <= 10)
                    Positioned(
                      left: AppSpacing.xs,
                      bottom: AppSpacing.xs,
                      child: _Badge(text: 'Còn $remaining suất', color: colors.warning),
                    ),
                  if (quantityInCart > 0)
                    Positioned(
                      left: AppSpacing.xs,
                      top: AppSpacing.xs,
                      child: _Badge(text: 'Trong giỏ: $quantityInCart', color: theme.colorScheme.primary),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(food.name, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: AppSpacing.xxs),
                    RatingLabel(average: food.averageRating, count: food.ratingCount),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: PriceText(food.price),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: food.hasOptions ? 'Chọn tùy chọn' : 'Thêm vào giỏ',
                          onPressed: _orderable ? onAdd : null,
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
    decoration: BoxDecoration(color: color, borderRadius: AppRadius.smAll),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white)),
  );
}
