import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../data/remote/menu_api.dart';
import '../../models/menu.dart';
import '../../models/review.dart';
import '../../providers/cart_provider.dart';
import '../../providers/menu_provider.dart';
import '../../widgets/async_value_view.dart';
import '../../widgets/common.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';
import 'menu_actions.dart';
import 'option_selection.dart';
import 'reviews_screen.dart';

/// Chi tiết món — FutureBuilder (qua AsyncValueView) tải GET /api/foods/{id}.
///
/// OrientationBuilder: dọc → ảnh lớn phía trên, nội dung cuộn bên dưới;
/// ngang (hoặc màn rộng) → ảnh bên trái, nội dung bên phải.
class FoodDetailScreen extends StatefulWidget {
  const FoodDetailScreen({super.key, required this.foodId, this.preview});

  final int foodId;

  /// Bản tóm tắt từ lưới (hiện tên/ảnh ngay trong lúc tải chi tiết).
  final FoodSummary? preview;

  @override
  State<FoodDetailScreen> createState() => _FoodDetailScreenState();
}

class _FoodDetailScreenState extends State<FoodDetailScreen> {
  late Future<FoodDetail> _future;
  late Future<FoodReviewPage> _reviewsFuture;

  @override
  void initState() {
    super.initState();
    // Tạo Future MỘT lần ở initState (không tạo trong build).
    _load();
  }

  void _load() {
    final api = context.read<MenuApi>();
    _future = api.food(widget.foodId);
    _reviewsFuture = api.reviews(widget.foodId, pageSize: 3);
  }

  void _retry() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return AsyncValueView<FoodDetail>(
      future: _future,
      onRetry: _retry,
      loading: _LoadingView(preview: widget.preview),
      builder: (context, food) => _FoodDetailBody(food: food, reviewsFuture: _reviewsFuture),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({this.preview});

  final FoodSummary? preview;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(preview?.name ?? '')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (preview != null)
          ClipRRect(
            borderRadius: AppRadius.lgAll,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Hero(tag: 'food-image-${preview!.id}', child: AppNetworkImage(preview!.imageUrl)),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        const SkeletonBox(height: 20, width: 200),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonBox(height: 14),
        const SizedBox(height: AppSpacing.xs),
        const SkeletonBox(height: 14, width: 240),
      ],
    ),
  );
}

class _FoodDetailBody extends StatefulWidget {
  const _FoodDetailBody({required this.food, required this.reviewsFuture});

  final FoodDetail food;
  final Future<FoodReviewPage> reviewsFuture;

  @override
  State<_FoodDetailBody> createState() => _FoodDetailBodyState();
}

class _FoodDetailBodyState extends State<_FoodDetailBody> {
  late final OptionSelection _selection = OptionSelection(widget.food);
  final _noteController = TextEditingController();
  final _scroll = ScrollController();
  int _quantity = 1;
  bool _adding = false;

  /// Tên món trên AppBar chỉ hiện khi đã cuộn qua ảnh (tránh lặp với tiêu đề lớn bên dưới ảnh).
  bool _showTitle = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.offset > _expandedHeight - kToolbarHeight;
      if (show != _showTitle) setState(() => _showTitle = show);
    });
  }

  double get _expandedHeight => (MediaQuery.sizeOf(context).width * 0.75).clamp(200.0, 360.0);

  FoodDetail get food => widget.food;
  bool get _orderable => food.summary.isAvailable && !food.summary.isSoldOut;

  /// Không cho chọn quá số suất còn lại hôm nay.
  int get _maxQuantity => (food.summary.remainingToday ?? 50).clamp(1, 50);

  @override
  void dispose() {
    _scroll.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _addToCart() async {
    setState(() => _adding = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CartProvider>().addFood(
        food.summary,
        quantity: _quantity,
        options: _selection.selectedOptions,
        note: _noteController.text,
      );
      if (!mounted) return;
      showAddedToCart(context, messenger, food.name, quantity: _quantity);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _adding = false);
        messenger.showSnackBar(SnackBar(content: Text('Không thêm được vào giỏ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = context.select<MenuProvider, bool>((m) => m.isFavorite(food.summary));
    final favoriteAction = IconButton(
      tooltip: isFavorite ? 'Bỏ yêu thích' : 'Yêu thích',
      onPressed: () => toggleFavorite(context, food.summary),
      icon: Icon(
        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: isFavorite ? context.appColors.cancelled : null,
      ),
    );

    return OrientationBuilder(
      builder: (context, orientation) {
        final wide = orientation == Orientation.landscape || MediaQuery.sizeOf(context).width >= 840;
        final content = _content(context);
        final image = Hero(tag: 'food-image-${food.id}', child: AppNetworkImage(food.summary.imageUrl));

        return Scaffold(
          bottomNavigationBar: _AddBar(
            orderable: _orderable,
            quantity: _quantity,
            maxQuantity: _maxQuantity,
            total: _selection.unitPrice * _quantity,
            missingGroup: _selection.firstInvalid?.name,
            busy: _adding,
            onQuantityChanged: (q) => setState(() => _quantity = q),
            onAdd: _addToCart,
          ),
          body: wide
              ? SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [const BackButton(), const Spacer(), favoriteAction]),
                              const SizedBox(height: AppSpacing.xs),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: AppRadius.lgAll,
                                  child: SizedBox.expand(child: image),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xs,
                            AppSpacing.md,
                            AppSpacing.md,
                            AppSpacing.xl,
                          ),
                          child: MaxWidthBox(child: content),
                        ),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      expandedHeight: _expandedHeight,
                      title: AnimatedOpacity(
                        opacity: _showTitle ? 1 : 0,
                        duration: AppDurations.fast,
                        child: Text(food.name),
                      ),
                      actions: [favoriteAction],
                      flexibleSpace: FlexibleSpaceBar(background: image),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
                      sliver: SliverToBoxAdapter(child: MaxWidthBox(child: content)),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final summary = food.summary;
    final remaining = summary.remainingToday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(food.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RatingLabel(average: summary.averageRating, count: summary.ratingCount),
            _Meta(icon: Icons.category_outlined, text: summary.categoryName),
            _Meta(icon: Icons.schedule_rounded, text: '~${summary.prepTimeMinutes} phút'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        PriceText(summary.price, style: theme.textTheme.titleMedium),
        if (!_orderable) ...[
          const SizedBox(height: AppSpacing.sm),
          _Notice(
            icon: Icons.block_rounded,
            color: context.appColors.cancelled,
            text: summary.isSoldOut
                ? 'Món đã hết suất hôm nay. Mời bạn quay lại vào ngày mai!'
                : 'Món đang tạm ngưng bán.',
          ),
        ] else if (remaining != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _Notice(
            icon: Icons.local_fire_department_rounded,
            color: remaining <= 10 ? context.appColors.warning : theme.colorScheme.onSurfaceVariant,
            text: 'Còn $remaining suất hôm nay',
          ),
        ],
        if (food.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(food.description, style: muted),
        ],
        for (final group in food.optionGroups) ...[
          const SizedBox(height: AppSpacing.lg),
          _OptionGroupView(
            group: group,
            selection: _selection,
            enabled: _orderable,
            onToggle: (option) => setState(() => _selection.toggle(group, option)),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('Ghi chú cho căn-tin', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _noteController,
          enabled: _orderable,
          maxLength: 200,
          maxLines: 2,
          minLines: 1,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'VD: ít cay, không hành...',
            prefixIcon: Icon(Icons.edit_note_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ReviewsSection(food: food, future: widget.reviewsFuture),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
      ),
    ],
  );
}

/// Một nhóm tùy chọn: radio (chọn 1) hoặc checkbox (chọn nhiều), kèm quy tắc và lỗi.
class _OptionGroupView extends StatelessWidget {
  const _OptionGroupView({required this.group, required this.selection, required this.enabled, required this.onToggle});

  final FoodOptionGroup group;
  final OptionSelection selection;
  final bool enabled;
  final ValueChanged<FoodOption> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = selection.errorOf(group);
    final primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(group.name, style: theme.textTheme.titleSmall)),
            Text(
              OptionSelection.ruleOf(group),
              style: theme.textTheme.bodySmall?.copyWith(
                color: error != null ? context.appColors.warning : theme.colorScheme.onSurfaceVariant,
                fontWeight: error != null ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Card(
          child: Column(
            children: [
              for (final (i, option) in group.options.indexed) ...[
                if (i > 0) const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
                Builder(
                  builder: (context) {
                    final selected = selection.isSelected(group, option);
                    final can = enabled && selection.canSelect(group, option);
                    return ListTile(
                      enabled: can || selected,
                      onTap: can ? () => onToggle(option) : null,
                      leading: Icon(
                        group.isSingleChoice
                            ? (selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded)
                            : (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
                        color: selected ? primary : null,
                      ),
                      title: Text(option.name),
                      trailing: !option.isAvailable
                          ? Text('Hết', style: theme.textTheme.bodySmall?.copyWith(color: context.appColors.cancelled))
                          : option.extraPrice > 0
                          ? Text(Money.signed(option.extraPrice), style: theme.textTheme.bodyMedium?.tabular)
                          : null,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Thanh dưới cùng: số lượng + nút "Thêm vào giỏ · tổng tiền" (nằm trong vùng ngón cái).
class _AddBar extends StatelessWidget {
  const _AddBar({
    required this.orderable,
    required this.quantity,
    required this.maxQuantity,
    required this.total,
    required this.missingGroup,
    required this.busy,
    required this.onQuantityChanged,
    required this.onAdd,
  });

  final bool orderable;
  final int quantity;
  final int maxQuantity;
  final int total;
  final String? missingGroup;
  final bool busy;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String label = !orderable
        ? 'Tạm hết món'
        : missingGroup != null
        ? 'Chọn $missingGroup'
        : 'Thêm vào giỏ · ${Money.format(total)}';
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      shadowColor: context.appColors.shadow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Row(
            children: [
              QuantityStepper(value: quantity, max: maxQuantity, onChanged: orderable ? onQuantityChanged : (_) {}),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: orderable && missingGroup == null && !busy ? onAdd : null,
                  child: busy
                      ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          // Chỉ thêm chữ số đều — giữ màu chữ của nút (trắng trên nền cam).
                          child: Text(label, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phần đánh giá: tổng quan (điểm, phân bố sao) + 3 đánh giá mới nhất + "Xem tất cả".
class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({required this.food, required this.future});

  final FoodDetail food;
  final Future<FoodReviewPage> future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<FoodReviewPage>(
      future: future,
      builder: (context, snapshot) {
        final header = Text('Đánh giá', style: theme.textTheme.titleMedium);
        switch (snapshot.connectionState) {
          case ConnectionState.none:
          case ConnectionState.waiting:
          case ConnectionState.active:
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: AppSpacing.sm),
                const SkeletonBox(height: 72),
              ],
            );
          case ConnectionState.done:
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  Text(ErrorView.messageOf(snapshot.error!), style: theme.textTheme.bodySmall),
                ],
              );
            }
            final page = snapshot.data!;
            if (page.summary.count == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Chưa có đánh giá. Hãy là người đầu tiên sau khi nhận món!',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: AppSpacing.sm),
                ReviewSummaryView(summary: page.summary),
                const SizedBox(height: AppSpacing.sm),
                for (final review in page.reviews.items) ReviewTile(review: review),
                if (page.summary.count > page.reviews.items.length)
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReviewsScreen(foodId: food.id, foodName: food.name, summary: page.summary),
                      ),
                    ),
                    child: Text('Xem tất cả ${page.summary.count} đánh giá'),
                  ),
              ],
            );
        }
      },
    );
  }
}
