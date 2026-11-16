import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/vn_time.dart';
import '../../data/remote/menu_api.dart';
import '../../models/review.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';

/// Tất cả đánh giá của một món: lọc theo số sao, sắp xếp, cuộn vô hạn (ListView.builder + ScrollController).
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key, required this.foodId, required this.foodName, this.summary});

  final int foodId;
  final String foodName;
  final ReviewSummary? summary;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  final _scroll = ScrollController();
  late ReviewSummary? _summary = widget.summary;
  final List<Review> _items = [];
  int? _rating;
  ReviewSort _sort = ReviewSort.newest;
  int _page = 0;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reload() {
    _generation++;
    _items.clear();
    _page = 0;
    _hasNext = true;
    _loading = false;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<MenuApi>().reviews(
        widget.foodId,
        page: _page + 1,
        rating: _rating,
        sort: _sort,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _summary = result.summary;
        _items.addAll(result.reviews.items);
        _page = result.reviews.page;
        _hasNext = result.reviews.hasNext;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _filter(int? rating) {
    if (rating == _rating) return;
    setState(() => _rating = rating);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(
        title: Text('Đánh giá · ${widget.foodName}'),
        actions: [
          PopupMenuButton<ReviewSort>(
            tooltip: 'Sắp xếp',
            icon: const Icon(Icons.swap_vert_rounded),
            initialValue: _sort,
            onSelected: (sort) {
              setState(() => _sort = sort);
              _reload();
            },
            itemBuilder: (_) => [for (final s in ReviewSort.values) PopupMenuItem(value: s, child: Text(s.label))],
          ),
        ],
      ),
      body: MaxWidthBox(
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            if (summary != null)
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.md),
                sliver: SliverToBoxAdapter(child: ReviewSummaryView(summary: summary)),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: kMinTapTarget,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: AppSpacing.pagePadding,
                  children: [
                    for (final star in [null, 5, 4, 3, 2, 1])
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: ChoiceChip(
                          showCheckmark: false,
                          label: Text(
                            star == null
                                ? 'Tất cả'
                                : '$star★${summary == null ? '' : ' (${summary.distribution[star] ?? 0})'}',
                          ),
                          selected: _rating == star,
                          onSelected: (_) => _filter(star),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_items.isEmpty && !_loading && _error == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(icon: Icons.rate_review_outlined, title: 'Chưa có đánh giá nào ở mức này'),
              ),
            if (_items.isEmpty && _error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(error: _error!, onRetry: _loadMore),
              ),
            SliverPadding(
              padding: AppSpacing.pagePadding,
              sliver: SliverList.builder(
                itemCount: _items.length,
                itemBuilder: (context, i) => ReviewTile(review: _items[i]),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: _loading
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : _error != null && _items.isNotEmpty
                      ? TextButton.icon(
                          onPressed: _loadMore,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Thử lại'),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Điểm trung bình (số lớn trong FittedBox) + thanh phân bố 5→1 sao.
class ReviewSummaryView extends StatelessWidget {
  const ReviewSummaryView({super.key, required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: FittedBox(
                      child: Text(
                        summary.average.toStringAsFixed(1),
                        style: theme.textTheme.headlineSmall?.tabular.copyWith(fontSize: 40),
                      ),
                    ),
                  ),
                  RatingStars(summary.average, size: 14),
                  const SizedBox(height: AppSpacing.xxs),
                  Text('${summary.count} đánh giá', style: muted),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                children: [
                  for (var star = 5; star >= 1; star--)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(width: 12, child: Text('$star', style: muted?.tabular)),
                          const SizedBox(width: AppSpacing.xxs),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: AppRadius.smAll,
                              child: LinearProgressIndicator(
                                value: summary.ratio(star),
                                minHeight: 6,
                                color: context.appColors.rating,
                                backgroundColor: theme.colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${summary.distribution[star] ?? 0}',
                              textAlign: TextAlign.end,
                              style: muted?.tabular,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Một đánh giá: tác giả, sao, thời gian, nhận xét, phản hồi của căn-tin.
class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: context.appColors.subtleBrand,
                child: Text(
                  review.authorName.isEmpty ? '?' : review.authorName[0],
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            review.authorName,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (review.isMine) ...[const SizedBox(width: AppSpacing.xxs), Text('(bạn)', style: muted)],
                      ],
                    ),
                    Text(VnTime.relative(review.createdAt), style: muted),
                  ],
                ),
              ),
              RatingStars(review.rating.toDouble(), size: 14),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(review.comment!, style: theme.textTheme.bodyMedium),
          ],
          if (review.staffReply != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(color: context.appColors.subtleBrand, borderRadius: AppRadius.mdAll),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.storefront_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        'Căn-tin phản hồi',
                        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(review.staffReply!, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
