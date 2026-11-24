import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../data/remote/menu_api.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/menu_provider.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';
import 'menu_actions.dart';

/// Tab Thực đơn: ô tìm kiếm · chip danh mục · sắp xếp / lọc · lưới món cuộn vô hạn.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final _scroll = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MenuProvider>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scroll.position;
    // Còn chưa tới ~1,5 màn hình nữa là hết → tải trang kế tiếp.
    if (position.extentAfter < position.viewportDimension * 1.5) context.read<MenuProvider>().loadMore();
    final show = position.pixels > position.viewportDimension;
    if (show != _showBackToTop) setState(() => _showBackToTop = show);
  }

  void _backToTop() => _scroll.animateTo(0, duration: AppDurations.slow, curve: Curves.easeOutCubic);

  Future<void> _apply(FoodQuery query) async {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await context.read<MenuProvider>().updateQuery(query);
  }

  @override
  Widget build(BuildContext context) {
    final menu = context.watch<MenuProvider>();
    final firstName = context.select<AuthProvider, String?>((a) => a.profile?.fullName.trim().split(' ').last);

    // MediaQuery: điện thoại xoay ngang chỉ cao ~400dp → thu gọn phần đầu (ô tìm kiếm thành nút trên AppBar,
    // Sắp xếp/Lọc chung hàng với danh mục) để dành chỗ cho lưới món.
    final shortScreen = MediaQuery.sizeOf(context).height < 520;

    return Scaffold(
      appBar: AppBar(
        title: Text(firstName == null ? 'Thực đơn' : 'Chào $firstName, hôm nay ăn gì?'),
        actions: [
          if (shortScreen)
            IconButton(
              tooltip: 'Tìm món',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.pushNamed(context, AppRoutes.search),
            ),
          IconButton(
            tooltip: 'Món yêu thích',
            icon: const Icon(Icons.favorite_border_rounded),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.favorites),
          ),
        ],
      ),
      floatingActionButton: AnimatedScale(
        scale: _showBackToTop ? 1 : 0,
        duration: AppDurations.normal,
        child: FloatingActionButton.small(
          tooltip: 'Lên đầu trang',
          onPressed: _backToTop,
          child: const Icon(Icons.arrow_upward_rounded),
        ),
      ),
      body: Column(
        children: [
          if (!shortScreen) const _SearchBox(),
          _CategoryBar(
            menu: menu,
            onSelected: (id) => _apply(menu.query.copyWith(categoryId: id)),
            leading: shortScreen ? _ToolBar(menu: menu, onChanged: _apply, inline: true) : null,
          ),
          if (!shortScreen) _ToolBar(menu: menu, onChanged: _apply),
          Expanded(child: _buildGrid(context, menu)),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, MenuProvider menu) {
    if (menu.items.isEmpty) {
      if (menu.isLoading || !menu.isLoaded && menu.error == null) return const _GridSkeleton();
      if (menu.error != null) return ErrorView(error: menu.error!, onRetry: menu.refresh);
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Không có món phù hợp',
        message: 'Thử chọn danh mục khác hoặc bỏ bớt bộ lọc.',
        actionLabel: 'Xóa bộ lọc',
        onAction: () => _apply(const FoodQuery()),
      );
    }

    final cart = context.watch<CartProvider>();
    // Hệ số cỡ chữ của hệ thống → ô lưới cao thêm tương ứng để chữ không bị cắt.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: menu.refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = Breakpoints.gridColumns(constraints.maxWidth);
              const gap = AppSpacing.sm;
              final cardWidth = (constraints.maxWidth - AppSpacing.md * 2 - gap * (columns - 1)) / columns;
              return GridView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xxl * 2),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  mainAxisExtent: cardWidth / FoodCard.imageAspect + FoodCard.infoHeight * textScale,
                ),
                itemCount: menu.items.length,
                itemBuilder: (context, index) {
                  final food = menu.items[index];
                  return FoodCard(
                    food: food,
                    isFavorite: menu.isFavorite(food),
                    quantityInCart: cart.quantityOf(food.id),
                    onTap: () => openFoodDetail(context, food),
                    onFavorite: () => toggleFavorite(context, food),
                    onAdd: () => quickAdd(context, food),
                  );
                },
              );
            },
          ),
        ),
        if (menu.isLoading || menu.isLoadingMore)
          const Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(minHeight: 3)),
        if (menu.loadMoreError != null)
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: Material(
              elevation: 2,
              borderRadius: AppRadius.mdAll,
              color: Theme.of(context).colorScheme.surface,
              child: ListTile(
                leading: const Icon(Icons.wifi_off_rounded),
                title: Text(ErrorView.messageOf(menu.loadMoreError!), maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: TextButton(onPressed: menu.loadMore, child: const Text('Thử lại')),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ô tìm kiếm (chạm để mở màn Tìm kiếm — có gợi ý từ lịch sử tìm kiếm).
class _SearchBox extends StatelessWidget {
  const _SearchBox();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      child: Material(
        color: theme.inputDecorationTheme.fillColor,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: () => Navigator.pushNamed(context, AppRoutes.search),
          child: SizedBox(
            height: kMinTapTarget + 4,
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.md),
                Icon(Icons.search_rounded, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Tìm món: cơm gà, trà sữa...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hàng chip danh mục cuộn ngang ("Tất cả" + từng danh mục).
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.menu, required this.onSelected, this.leading});

  final MenuProvider menu;
  final ValueChanged<int?> onSelected;

  /// Đặt trước các chip danh mục (màn thấp: nút Sắp xếp/Lọc).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final selected = menu.query.categoryId;
    final chips = <(int?, String, IconData)>[
      (null, 'Tất cả', Icons.restaurant_menu_rounded),
      for (final c in menu.categories) (c.id, c.name, categoryIcon(c.icon)),
    ];
    return SizedBox(
      height: kMinTapTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: AppSpacing.pagePadding,
        itemCount: chips.length + (leading == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          if (leading != null && index == 0) return leading!;
          final (id, label, icon) = chips[leading == null ? index : index - 1];
          final isSelected = id == selected;
          return ChoiceChip(
            avatar: Icon(icon, size: 18, color: isSelected ? Theme.of(context).colorScheme.primary : null),
            showCheckmark: false,
            label: Text(label),
            selected: isSelected,
            onSelected: (_) => onSelected(id),
          );
        },
      ),
    );
  }
}

/// Sắp xếp + Lọc + số món tìm thấy.
class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.menu, required this.onChanged, this.inline = false});

  final MenuProvider menu;
  final ValueChanged<FoodQuery> onChanged;

  /// Nằm trong hàng chip danh mục (không lề riêng, có vạch ngăn phía sau).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final query = menu.query;
    final filters = query.extraFilterCount;
    return Padding(
      padding: inline
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xxs),
      // Màn rất hẹp + chữ lớn: thu nhỏ nhẹ cả hàng (FittedBox) thay vì tràn.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ActionChip(
              avatar: const Icon(Icons.swap_vert_rounded, size: 18),
              label: Text(query.sort.label),
              onPressed: () async {
                final sort = await showModalBottomSheet<FoodSort>(
                  context: context,
                  builder: (_) => _SortSheet(current: query.sort),
                );
                if (sort != null) onChanged(query.copyWith(sort: sort));
              },
            ),
            const SizedBox(width: AppSpacing.xs),
            ActionChip(
              avatar: Badge(
                isLabelVisible: filters > 0,
                label: Text('$filters'),
                child: const Icon(Icons.tune_rounded, size: 18),
              ),
              label: const Text('Lọc'),
              onPressed: () async {
                final result = await showModalBottomSheet<FoodQuery>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => _FilterSheet(query: query),
                );
                if (result != null) onChanged(result);
              },
            ),
            if (inline) const VerticalDivider(indent: AppSpacing.sm, endIndent: AppSpacing.sm, width: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.current});

  final FoodSort current;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
          child: Text('Sắp xếp theo', style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final sort in FoodSort.values)
          ListTile(
            title: Text(sort.label),
            trailing: sort == current ? Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary) : null,
            onTap: () => Navigator.pop(context, sort),
          ),
      ],
    ),
  );
}

/// Khoảng giá đặt sẵn (chọn một chạm thay vì gõ số).
const _pricePresets = <(String, int?, int?)>[
  ('Mọi mức giá', null, null),
  ('Dưới 20.000đ', null, 19999),
  ('20.000đ – 35.000đ', 20000, 35000),
  ('Trên 35.000đ', 35001, null),
];

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.query});

  final FoodQuery query;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late int? _min = widget.query.minPrice;
  late int? _max = widget.query.maxPrice;
  late bool _availableOnly = widget.query.availableOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lọc món', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Text('Khoảng giá', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final (label, min, max) in _pricePresets)
                  ChoiceChip(
                    label: Text(label),
                    selected: _min == min && _max == max,
                    onSelected: (_) => setState(() {
                      _min = min;
                      _max = max;
                    }),
                  ),
              ],
            ),
            if (_min != null || _max != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  if (_min != null) 'từ ${Money.format(_min!)}',
                  if (_max != null) 'đến ${Money.format(_max!)}',
                ].join(' '),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Chỉ món còn bán'),
              subtitle: const Text('Ẩn món đã hết suất hôm nay'),
              value: _availableOnly,
              onChanged: (v) => setState(() => _availableOnly = v),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      widget.query.copyWith(minPrice: null, maxPrice: null, availableOnly: false),
                    ),
                    child: const Text('Đặt lại'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      widget.query.copyWith(minPrice: _min, maxPrice: _max, availableOnly: _availableOnly),
                    ),
                    child: const Text('Áp dụng'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton dạng lưới trong lúc tải trang đầu.
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = Breakpoints.gridColumns(constraints.maxWidth);
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: 0.72,
        ),
        itemCount: columns * 3,
        itemBuilder: (_, _) => Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            color: context.appColors.subtleBrand,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SkeletonBox(radius: AppRadius.lg)),
              Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 14),
                    SizedBox(height: AppSpacing.xs),
                    SkeletonBox(width: 64, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
