import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/vn_time.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/review_api.dart';
import '../../models/review.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';

/// Đánh giá của tôi — cuộn vô hạn (ListView.builder + ScrollController). Hiện lý do nếu bị ẩn và
/// câu trả lời của căn-tin; sửa (trong hạn) / xóa ngay trên danh sách.
class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  final _scroll = ScrollController();
  final List<Review> _items = [];
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
      final page = await context.read<ReviewApi>().mine(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _page = page.page;
        _hasNext = page.hasNext;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(int index) async {
    final review = _items[index];
    final result = await showModalBottomSheet<(int, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditReviewSheet(review: review),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await context.read<ReviewApi>().update(review.id, rating: result.$1, comment: result.$2);
      setState(() => _items[index] = updated);
      messenger.showSnackBar(const SnackBar(content: Text('Đã lưu đánh giá.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(int index) async {
    final review = _items[index];
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<ReviewApi>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa đánh giá?'),
        content: Text('Đánh giá cho "${review.foodName}" sẽ bị xóa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Giữ lại')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.delete(review.id);
      setState(() => _items.removeWhere((r) => r.id == review.id));
      messenger.showSnackBar(const SnackBar(content: Text('Đã xóa đánh giá.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đánh giá của tôi')),
      body: MaxWidthBox(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_items.isEmpty) {
      if (_loading) return const SkeletonList();
      if (_error != null) return ErrorView(error: _error!, onRetry: _loadMore);
      return const EmptyState(
        icon: Icons.rate_review_outlined,
        title: 'Bạn chưa đánh giá món nào',
        message: 'Sau khi nhận món, mở đơn đã hoàn thành và chấm sao để căn-tin biết bạn thích gì.',
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _items.length + (_hasNext ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _MyReviewCard(review: _items[i], onEdit: () => _edit(i), onDelete: () => _delete(i)),
          );
        },
      ),
    );
  }
}

class _MyReviewCard extends StatelessWidget {
  const _MyReviewCard({required this.review, required this.onEdit, required this.onDelete});

  final Review review;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final colors = context.appColors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.pushNamed(context, AppRoutes.food, arguments: review.foodId),
                    child: Text(review.foodName, style: theme.textTheme.titleSmall),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Tùy chọn',
                  onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => [
                    if (review.canEdit) const PopupMenuItem(value: 'edit', child: Text('Sửa đánh giá')),
                    const PopupMenuItem(value: 'delete', child: Text('Xóa')),
                  ],
                ),
              ],
            ),
            Row(
              children: [
                RatingStars(review.rating.toDouble(), size: 16),
                const SizedBox(width: AppSpacing.xs),
                Text(VnTime.relative(review.createdAt), style: muted),
                if (!review.canEdit && !review.isHidden) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text('· hết hạn sửa', style: muted),
                ],
              ],
            ),
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Text(review.comment!, style: theme.textTheme.bodyMedium),
              ),
            ],
            if (review.isHidden)
              _Banner(
                color: colors.cancelled,
                icon: Icons.visibility_off_outlined,
                text: 'Đã bị ẩn khỏi trang món: ${review.hiddenReason ?? 'vi phạm quy định'}',
              ),
            if (review.staffReply != null)
              _Banner(
                color: theme.colorScheme.primary,
                icon: Icons.storefront_rounded,
                text: 'Căn-tin: ${review.staffReply}',
              ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, AppSpacing.sm, 0),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: AppRadius.mdAll),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    ),
  );
}

class _EditReviewSheet extends StatefulWidget {
  const _EditReviewSheet({required this.review});

  final Review review;

  @override
  State<_EditReviewSheet> createState() => _EditReviewSheetState();
}

class _EditReviewSheetState extends State<_EditReviewSheet> {
  late int _rating = widget.review.rating;
  late final _comment = TextEditingController(text: widget.review.comment ?? '');

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.review.foodName, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        StarRatingInput(value: _rating, onChanged: (v) => setState(() => _rating = v)),
        TextField(
          controller: _comment,
          maxLength: 500,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(hintText: 'Nhận xét'),
        ),
        const SizedBox(height: AppSpacing.xs),
        FilledButton(onPressed: () => Navigator.pop(context, (_rating, _comment.text)), child: const Text('Lưu')),
      ],
    ),
  );
}
