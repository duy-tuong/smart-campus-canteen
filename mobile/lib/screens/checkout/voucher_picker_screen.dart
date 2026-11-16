import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../core/utils/vn_time.dart';
import '../../data/remote/order_api.dart';
import '../../models/checkout.dart';
import '../../widgets/async_value_view.dart';
import '../../widgets/state_views.dart';

/// Chọn mã giảm giá (mở bằng Navigator.push, trả về mã qua Navigator.pop):
/// danh sách mã tôi dùng được (FutureBuilder) + ô nhập mã tay. Trả '' = không dùng mã.
class VoucherPickerScreen extends StatefulWidget {
  const VoucherPickerScreen({super.key, required this.subtotal, this.current});

  final int subtotal;
  final String? current;

  @override
  State<VoucherPickerScreen> createState() => _VoucherPickerScreenState();
}

class _VoucherPickerScreenState extends State<VoucherPickerScreen> {
  late final _codeController = TextEditingController(text: widget.current);
  late Future<List<AvailableVoucher>> _future = context.read<OrderApi>().availableVouchers();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _apply() {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mã giảm giá'),
        actions: [
          if (widget.current != null)
            TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Không dùng mã')),
        ],
      ),
      body: MaxWidthBox(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _apply(),
                      maxLength: 30,
                      decoration: const InputDecoration(
                        hintText: 'Nhập mã, VD: GIAM10',
                        prefixIcon: Icon(Icons.local_offer_outlined),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(onPressed: _apply, child: const Text('Áp dụng')),
                ],
              ),
            ),
            Expanded(
              child: AsyncValueView<List<AvailableVoucher>>(
                future: _future,
                onRetry: () => setState(() {
                  _future = context.read<OrderApi>().availableVouchers();
                }),
                isEmpty: (list) => list.isEmpty,
                empty: const EmptyState(
                  icon: Icons.local_offer_outlined,
                  title: 'Chưa có mã nào cho bạn',
                  message: 'Theo dõi thông báo của căn-tin để nhận mã giảm giá mới.',
                ),
                builder: (context, vouchers) => ListView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                  itemCount: vouchers.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _VoucherCard(
                      voucher: vouchers[i],
                      subtotal: widget.subtotal,
                      selected: vouchers[i].code == widget.current,
                      onUse: () => Navigator.pop(context, vouchers[i].code),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ voucher dạng "vé": cột trái màu cam với mức giảm, phải là điều kiện + nút Dùng.
class _VoucherCard extends StatelessWidget {
  const _VoucherCard({required this.voucher, required this.subtotal, required this.selected, required this.onUse});

  final AvailableVoucher voucher;
  final int subtotal;
  final bool selected;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final shortBy = voucher.minOrderAmount - subtotal;
    final usable = shortBy <= 0;
    final estimate = voucher.estimateFor(subtotal);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 88,
              color: usable ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: FittedBox(
                child: Text(
                  voucher.discountType == DiscountType.percent
                      ? '-${voucher.discountValue}%'
                      : '-${Money.compact(voucher.discountValue)}',
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(voucher.code, style: theme.textTheme.titleSmall),
                    Text(voucher.title, style: theme.textTheme.bodyMedium),
                    if (voucher.description.isNotEmpty) Text(voucher.description, style: muted),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      [
                        if (voucher.minOrderAmount > 0) 'Đơn từ ${Money.format(voucher.minOrderAmount)}',
                        'HSD ${VnTime.date(voucher.endAt)}',
                        if (voucher.remainingForMe != null) 'Còn ${voucher.remainingForMe} lượt',
                      ].join(' · '),
                      style: muted,
                    ),
                    if (!usable)
                      Text(
                        'Mua thêm ${Money.format(shortBy)} để dùng mã',
                        style: theme.textTheme.bodySmall?.copyWith(color: context.appColors.warning),
                      )
                    else if (estimate > 0)
                      Text(
                        'Dự kiến giảm ${Money.format(estimate)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: context.appColors.success),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Center(
                child: selected
                    ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                    : TextButton(onPressed: usable ? onUse : null, child: const Text('Dùng')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
