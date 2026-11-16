import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../core/utils/vn_time.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../providers/home_tabs.dart';

/// Đặt món thành công — "khoảnh khắc đỉnh" của hành trình: dấu tích có hiệu ứng, MÃ NHẬN MÓN cỡ lớn
/// (FittedBox), giờ nhận, tình trạng thanh toán, và bước tiếp theo rõ ràng.
class OrderPlacedScreen extends StatefulWidget {
  const OrderPlacedScreen({super.key, required this.order});

  final OrderDetail order;

  @override
  State<OrderPlacedScreen> createState() => _OrderPlacedScreenState();
}

class _OrderPlacedScreenState extends State<OrderPlacedScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int tab) {
    context.read<HomeTabs>().select(tab);
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final colors = context.appColors;
    final paid = order.paymentStatus == PaymentStatus.paid;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(HomeTabs.menu);
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: MaxWidthBox(
              maxWidth: 480,
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  ScaleTransition(
                    scale: CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: colors.success.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: colors.success.withValues(alpha: 0.25), blurRadius: 32)],
                      ),
                      child: Icon(Icons.check_rounded, size: 56, color: colors.success),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Đặt món thành công!', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    paid
                        ? 'Đã nhận thanh toán. Căn-tin đang chuẩn bị món cho bạn.'
                        : 'Căn-tin đã nhận đơn. Thanh toán khi nhận món tại quầy.',
                    style: muted,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          Text('Mã nhận món', style: muted),
                          // FittedBox: mã luôn to nhất có thể mà không tràn — đưa cho quầy xem từ xa.
                          SizedBox(
                            height: 72,
                            child: FittedBox(
                              child: Text(
                                order.pickupCode,
                                style: theme.textTheme.displaySmall?.tabular.copyWith(
                                  fontSize: 56,
                                  letterSpacing: 4,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const Divider(height: AppSpacing.xl),
                          _InfoRow(
                            icon: Icons.schedule_rounded,
                            label: 'Nhận món',
                            value: order.pickupTime != null
                                ? 'Lúc ${VnTime.time(order.pickupTime!)} hôm nay'
                                : order.estimatedReadyAt != null
                                ? 'Dự kiến ${VnTime.time(order.estimatedReadyAt!)}'
                                : 'Sớm nhất có thể',
                          ),
                          _InfoRow(icon: Icons.restaurant_rounded, label: 'Món', value: '${order.totalItems} phần'),
                          _InfoRow(
                            icon: paid ? Icons.verified_rounded : Icons.payments_outlined,
                            label: order.paymentMethod.label,
                            value: order.paymentStatus.label,
                            valueColor: paid ? colors.success : null,
                          ),
                          _InfoRow(
                            icon: Icons.receipt_long_rounded,
                            label: 'Tổng cộng',
                            value: Money.format(order.totalAmount),
                            valueColor: colors.price,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: () => _goTo(HomeTabs.orders),
                    icon: const Icon(Icons.track_changes_rounded),
                    label: const Text('Theo dõi đơn'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(onPressed: () => _goTo(HomeTabs.menu), child: const Text('Tiếp tục xem thực đơn')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value, this.valueColor});

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(value, style: theme.textTheme.titleSmall?.tabular.copyWith(color: valueColor)),
        ],
      ),
    );
  }
}
