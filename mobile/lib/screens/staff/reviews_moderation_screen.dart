import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/vn_time.dart';
import '../../data/remote/staff_api.dart';
import '../../models/review.dart';
import '../../widgets/food_widgets.dart';
import '../../widgets/state_views.dart';
import 'manage_hub_screen.dart';

enum _ReviewFilter {
  unreplied('Chưa trả lời'),
  all('Tất cả'),
  hidden('Đã ẩn');

  const _ReviewFilter(this.label);
  final String label;
}

/// Kiểm duyệt đánh giá: lọc "Chưa trả lời" (việc cần làm), trả lời khách, ẩn đánh giá vi phạm (kèm lý do), hiện lại.
class ReviewsModerationScreen extends StatefulWidget {
  const ReviewsModerationScreen({super.key});

  @override
  State<ReviewsModerationScreen> createState() => _ReviewsModerationScreenState();
}

class _ReviewsModerationScreenState extends State<ReviewsModerationScreen> {
  late final StaffApi _api = context.read<StaffApi>();
  _ReviewFilter _filter = _ReviewFilter.unreplied;
  List<Review> _items = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.reviews(
        hasReply: _filter == _ReviewFilter.unreplied ? false : null,
        isHidden: switch (_filter) {
          _ReviewFilter.hidden => true,
          _ReviewFilter.unreplied => false,
          _ReviewFilter.all => null,
        },
      );
      if (mounted) setState(() => _items = page.items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askText({required String title, required String label, String? initial, int minLength = 1}) =>
      TextPromptDialog.show(context, title: title, label: label, initial: initial, minLength: minLength);

  Future<void> _apply(int index, Future<Review> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action();
      setState(() {
        final list = [..._items];
        // Không còn khớp bộ lọc (VD: vừa trả lời trong tab "Chưa trả lời") → bỏ khỏi danh sách.
        final stillMatches = switch (_filter) {
          _ReviewFilter.unreplied => updated.staffReply == null && !updated.isHidden,
          _ReviewFilter.hidden => updated.isHidden,
          _ReviewFilter.all => true,
        };
        stillMatches ? list[index] = updated : list.removeAt(index);
        _items = list;
      });
      messenger.showSnackBar(SnackBar(content: Text(done), duration: const Duration(seconds: 2)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorView.messageOf(e))));
    }
  }

  Future<void> _reply(int i) async {
    final text = await _askText(
      title: 'Trả lời ${_items[i].authorName}',
      label: 'Nội dung trả lời',
      initial: _items[i].staffReply,
    );
    if (text != null) {
      await _apply(i, () => _api.replyReview(_items[i].id, text), 'Đã gửi trả lời — khách sẽ nhận thông báo.');
    }
  }

  Future<void> _toggleHidden(int i) async {
    final r = _items[i];
    if (r.isHidden) {
      await _apply(i, () => _api.setReviewHidden(r.id, false), 'Đã hiện lại đánh giá.');
      return;
    }
    final reason = await _askText(title: 'Ẩn đánh giá này?', label: 'Lý do (khách sẽ thấy)', minLength: 3);
    if (reason != null) await _apply(i, () => _api.setReviewHidden(r.id, true, reason: reason), 'Đã ẩn đánh giá.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đánh giá của khách')),
      body: Column(
        children: [
          Padding(
            padding: AppSpacing.pagePadding,
            child: SegmentedButton<_ReviewFilter>(
              segments: [for (final f in _ReviewFilter.values) ButtonSegment(value: f, label: Text(f.label))],
              selected: {_filter},
              onSelectionChanged: (s) {
                setState(() => _filter = s.first);
                _load();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: _items.isEmpty
                ? (_loading
                      ? const SkeletonList()
                      : _error != null
                      ? ErrorView(error: _error!, onRetry: _load)
                      : EmptyState(
                          icon: Icons.mark_chat_read_outlined,
                          title: _filter == _ReviewFilter.unreplied ? 'Đã trả lời hết đánh giá' : 'Không có đánh giá',
                        ))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: formWidth(
                      ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: _items.length,
                        itemBuilder: (context, i) => _ModerationCard(
                          review: _items[i],
                          onReply: () => _reply(i),
                          onToggleHidden: () => _toggleHidden(i),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModerationCard extends StatelessWidget {
  const _ModerationCard({required this.review, required this.onReply, required this.onToggleHidden});

  final Review review;
  final VoidCallback onReply;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(review.foodName, style: theme.textTheme.titleSmall)),
                RatingStars(review.rating.toDouble(), size: 16),
              ],
            ),
            Text('${review.authorName} · ${VnTime.relative(review.createdAt)}', style: muted),
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(review.comment!, style: theme.textTheme.bodyMedium),
            ],
            if (review.isHidden)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Đang ẩn: ${review.hiddenReason ?? ''}',
                  style: theme.textTheme.bodySmall?.copyWith(color: context.appColors.cancelled),
                ),
              ),
            if (review.staffReply != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: AppSpacing.xs),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(color: context.appColors.subtleBrand, borderRadius: AppRadius.mdAll),
                child: Text('Căn-tin: ${review.staffReply}', style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: AppSpacing.xs),
            // Wrap: màn hẹp / chữ lớn thì hai nút tự xuống dòng thay vì tràn.
            // Bọc SizedBox full-width để WrapAlignment.end thật sự đẩy nút sang phải.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton.icon(
                    onPressed: onToggleHidden,
                    icon: Icon(review.isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    label: Text(review.isHidden ? 'Hiện lại' : 'Ẩn'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onReply,
                    icon: const Icon(Icons.reply_rounded),
                    label: Text(review.staffReply == null ? 'Trả lời' : 'Sửa trả lời'),
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
