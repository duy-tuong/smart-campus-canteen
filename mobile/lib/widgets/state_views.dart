import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';
import '../data/remote/api_exception.dart';

/// Trạng thái trống: biểu tượng + tiêu đề + mô tả + nút hành động (không để màn hình "chết").
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: context.appColors.subtleBrand, shape: BoxShape.circle),
                child: Icon(icon, size: 48, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Màn lỗi kèm nút "Thử lại". Mất mạng → biểu tượng wifi và lời nhắc kiểm tra địa chỉ máy chủ.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isNetwork = error is ApiException && (error as ApiException).isNetwork;
    return EmptyState(
      icon: isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: isNetwork ? 'Không có kết nối' : 'Đã có lỗi xảy ra',
      message: messageOf(error),
      actionLabel: onRetry == null ? null : 'Thử lại',
      onAction: onRetry,
    );
  }

  /// Câu thông báo tiếng Việt cho một lỗi bất kỳ (dùng cả cho SnackBar).
  static String messageOf(Object error) =>
      error is ApiException ? error.message : 'Không thể tải dữ liệu. Vui lòng thử lại.';
}

/// Khối xám nhấp nháy giữ chỗ trong lúc tải (skeleton) — người dùng thấy trước bố cục sắp hiện.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 16, this.radius = AppRadius.sm});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.04, end: 0.10).animate(_controller),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// Danh sách skeleton dạng ListTile — mặc định cho trạng thái chờ của danh sách.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) => ListView.separated(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(AppSpacing.md),
    itemCount: itemCount,
    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
    itemBuilder: (_, _) => const Row(
      children: [
        SkeletonBox(width: 56, height: 56, radius: AppRadius.md),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(height: 14),
              SizedBox(height: AppSpacing.xs),
              SkeletonBox(width: 120, height: 12),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Hộp thoại nhập một đoạn chữ (lý do hủy, trả lời đánh giá...). Tự giữ TextEditingController và chỉ dispose
/// khi hộp thoại bị gỡ khỏi cây widget — dispose ngay sau `showDialog` sẽ lỗi vì TextField vẫn còn trên màn
/// hình trong lúc hiệu ứng đóng hộp thoại đang chạy.
class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    required this.label,
    this.initial,
    this.minLength = 1,
    this.maxLength = 500,
    this.confirmLabel = 'Lưu',
    this.suggestions = const [],
  });

  final String title;
  final String label;
  final String? initial;
  final int minLength;
  final int maxLength;
  final String confirmLabel;

  /// Chạm để điền nhanh (VD: các lý do hủy thường gặp).
  final List<String> suggestions;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String label,
    String? initial,
    int minLength = 1,
    int maxLength = 500,
    String confirmLabel = 'Lưu',
    List<String> suggestions = const [],
  }) => showDialog<String>(
    context: context,
    builder: (_) => TextPromptDialog(
      title: title,
      label: label,
      initial: initial,
      minLength: minLength,
      maxLength: maxLength,
      confirmLabel: confirmLabel,
      suggestions: suggestions,
    ),
  );

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.length < widget.minLength) {
      setState(() => _error = 'Cần ít nhất ${widget.minLength} ký tự.');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.suggestions.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final s in widget.suggestions) ActionChip(label: Text(s), onPressed: () => _controller.text = s),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextField(
          controller: _controller,
          autofocus: widget.suggestions.isEmpty,
          maxLength: widget.maxLength,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(labelText: widget.label, errorText: _error),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
      FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ],
  );
}
