import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/remote/menu_api.dart';
import '../../models/menu.dart';
import '../../providers/home_tabs.dart';
import '../../providers/menu_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';
import 'menu_actions.dart';

/// Món yêu thích (GET /api/users/me/favorites) — cuộn vô hạn, bỏ tim ngay trên danh sách.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _scroll = ScrollController();
  final List<FoodSummary> _items = [];
  int _page = 0;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _items.clear();
    _page = 0;
    _hasNext = true;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<MenuApi>().favorites(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _page = result.page;
        _hasNext = result.hasNext;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = context.watch<MenuProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Món yêu thích')),
      body: MaxWidthBox(child: _body(context, menu)),
    );
  }

  Widget _body(BuildContext context, MenuProvider menu) {
    if (_items.isEmpty) {
      if (_loading) return const SkeletonList();
      if (_error != null) return ErrorView(error: _error!, onRetry: _loadMore);
      return EmptyState(
        icon: Icons.favorite_border_rounded,
        title: 'Chưa có món yêu thích',
        message: 'Chạm vào trái tim trên món bạn thích để lưu lại và đặt nhanh lần sau.',
        actionLabel: 'Khám phá thực đơn',
        onAction: () {
          context.read<HomeTabs>().select(HomeTabs.menu);
          Navigator.pop(context);
        },
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: _loading
                    ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const SizedBox.shrink(),
              ),
            );
          }
          final food = _items[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Card(
              child: InkWell(
                onTap: () => openFoodDetail(context, food),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      AppNetworkImage(food.imageUrl, width: 72, height: 72, borderRadius: AppRadius.mdAll),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(food.name, style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: AppSpacing.xxs),
                            RatingLabel(average: food.averageRating, count: food.ratingCount),
                            const SizedBox(height: AppSpacing.xxs),
                            PriceText(food.price),
                          ],
                        ),
                      ),
                      FavoriteButton(isFavorite: menu.isFavorite(food), onPressed: () => toggleFavorite(context, food)),
                      const SizedBox(width: AppSpacing.xs),
                      IconButton.filledTonal(
                        tooltip: food.hasOptions ? 'Chọn tùy chọn' : 'Thêm vào giỏ',
                        onPressed: food.isSoldOut || !food.isAvailable ? null : () => quickAdd(context, food),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
