import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/vn_time.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/review_api.dart';
import '../../models/review.dart';
import '../../widgets/async_value_view.dart';
import '../../widgets/common.dart';
import '../../widgets/food_widgets.dart';

/// Đánh giá đơn hàng: chấm sao + nhận xét TỪNG món trong đơn đã hoàn thành (trong hạn 7 ngày).
/// Món đã đánh giá → hiện sẵn để sửa / xóa.
class ReviewOrderScreen extends StatefulWidget {
  const ReviewOrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<ReviewOrderScreen> createState() => _ReviewOrderScreenState();
}

class _ReviewOrderScreenState extends State<ReviewOrderScreen> {
  late Future<OrderReviews> _future;

  /// Món đã có đánh giá — cập nhật ngay khi từng thẻ gửi / xóa (không phải tải lại cả màn).
  Set<int>? _reviewed;

  @override
  void initState() {
    super.initState();
    _future = context.read<ReviewApi>().forOrder(widget.orderId);
  }

  void _reload() => setState(() {
    _reviewed = null;
    _future = context.read<ReviewApi>().forOrder(widget.orderId);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đánh giá món')),
      body: AsyncValueView<OrderReviews>(
        future: _future,
        onRetry: _reload,
        isEmpty: (r) => r.items.isEmpty,
        builder: (context, data) {
          final theme = Theme.of(context);
          final reviewedIds = _reviewed ??= {
            for (final i in data.items)
              if (i.myReview != null) i.foodId,
          };
          final reviewed = reviewedIds.length;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              MaxWidthBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      data.canReview
                          ? 'Món hôm nay thế nào? Đánh giá giúp căn-tin nấu ngon hơn.'
                          : 'Đơn này không còn trong hạn đánh giá.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (data.canReview && data.reviewDeadline != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Đánh giá hoặc sửa trước ${VnTime.dateTime(data.reviewDeadline!)} · đã đánh giá $reviewed/${data.items.length} món',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    for (final item in data.items) ...[
                      _ReviewItemCard(
                        key: ValueKey(item.foodId),
                        orderId: data.orderId,
                        item: item,
                        canReview: data.canReview,
                        onChanged: _reload,
                        onReviewed: (done) => setState(() {
                          done ? reviewedIds.add(item.foodId) : reviewedIds.remove(item.foodId);
                        }),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReviewItemCard extends StatefulWidget {
  const _ReviewItemCard({
    super.key,
    required this.orderId,
    required this.item,
    required this.canReview,
    required this.onChanged,
    required this.onReviewed,
  });

  final String orderId;
  final OrderReviewItem item;
  final bool canReview;
  final VoidCallback onChanged;

  /// Báo lên màn cha: món này vừa có (true) / vừa xóa (false) đánh giá.
  final ValueChanged<bool> onReviewed;

  @override
  State<_ReviewItemCard> createState() => _ReviewItemCardState();
}

class _ReviewItemCardState extends State<_ReviewItemCard> {
  late Review? _review = widget.item.myReview;
  late int _rating = _review?.rating ?? 0;
  late final _comment = TextEditingController(text: _review?.comment ?? '');
  bool _busy = false;

  bool get _editable => widget.canReview && (_review?.canEdit ?? true);

  /// Có thay đổi chưa lưu (để bật nút Lưu).
  bool get _dirty => _rating != (_review?.rating ?? 0) || _comment.text.trim() != (_review?.comment ?? '');

  @override
  void initState() {
    super.initState();
    _comment.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final api = context.read<ReviewApi>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final saved = _review == null
          ? await api.create(widget.orderId, foodId: widget.item.foodId, rating: _rating, comment: _comment.text)
          : await api.update(_review!.id, rating: _rating, comment: _comment.text);
      setState(() => _review = saved);
      widget.onReviewed(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_rating >= 4 ? 'Cảm ơn bạn! Căn-tin rất vui vì bạn thích món này.' : 'Cảm ơn góp ý của bạn!'),
          ),
        );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      // Có người khác/thiết bị khác vừa đánh giá → tải lại để thấy đánh giá hiện có.
      if (e.code == 'REVIEW_EXISTS') widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final review = _review;
    if (review == null) return;
    final api = context.read<ReviewApi>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa đánh giá?'),
        content: Text('Đánh giá cho "${widget.item.foodName}" sẽ bị xóa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Giữ lại')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await api.delete(review.id);
      setState(() {
        _review = null;
        widget.onReviewed(false);
        _rating = 0;
        _comment.clear();
      });
      messenger.showSnackBar(const SnackBar(content: Text('Đã xóa đánh giá.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final review = _review;
    final hidden = review?.isHidden ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppNetworkImage(widget.item.imageUrl, width: 48, height: 48, borderRadius: AppRadius.smAll),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(widget.item.foodName, style: theme.textTheme.titleSmall)),
                if (review != null && !hidden)
                  Icon(Icons.check_circle_rounded, color: context.appColors.success, semanticLabel: 'Đã đánh giá'),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            StarRatingInput(
              value: _rating,
              enabled: _editable && !_busy,
              onChanged: (v) => setState(() => _rating = v),
            ),
            if (hidden)
              _Note(
                icon: Icons.visibility_off_outlined,
                color: context.appColors.cancelled,
                text: 'Đánh giá đã bị ẩn: ${review!.hiddenReason ?? 'vi phạm quy định'}',
              ),
            if (_editable) ...[
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _comment,
                enabled: !_busy,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(hintText: 'Nhận xét (không bắt buộc): vị, lượng, nhiệt độ...'),
              ),
              Row(
                children: [
                  if (review != null)
                    TextButton.icon(
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Xóa'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _rating == 0 || !_dirty || _busy ? null : _save,
                    child: _busy
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(review == null ? 'Gửi đánh giá' : 'Lưu thay đổi'),
                  ),
                ],
              ),
            ] else if (review?.comment != null && review!.comment!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(review.comment!, style: theme.textTheme.bodyMedium),
            ],
            if (review?.staffReply != null)
              _Note(
                icon: Icons.storefront_rounded,
                color: theme.colorScheme.primary,
                text: 'Căn-tin: ${review!.staffReply}',
              ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Container(
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
