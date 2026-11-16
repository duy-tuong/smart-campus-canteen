import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../core/utils/vn_time.dart';
import '../../data/firebase/realtime_service.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/staff_api.dart';
import '../../models/enums.dart';
import '../../models/live.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

/// Bước tiếp theo của một đơn trên bảng (nút chính của thẻ).
class BoardStep {
  const BoardStep(this.label, this.target, this.icon);

  final String label;
  final OrderStatus target;
  final IconData icon;

  static BoardStep? of(OrderLive o) => switch (o.status) {
    OrderStatus.received => const BoardStep('Bắt đầu nấu', OrderStatus.cooking, Icons.local_fire_department_rounded),
    OrderStatus.cooking => const BoardStep('Xong — mời nhận', OrderStatus.ready, Icons.notifications_active_rounded),
    OrderStatus.ready => const BoardStep('Đã giao món', OrderStatus.completed, Icons.check_circle_rounded),
    _ => null,
  };

  /// Đơn chuyển khoản chưa trả tiền → chưa được nấu (backend trả PAYMENT_REQUIRED).
  static bool waitingPayment(OrderLive o) =>
      o.paymentMethod == PaymentMethod.bankTransfer && o.paymentStatus != PaymentStatus.paid;
}

/// Bảng đơn của căn-tin — StreamBuilder trên Firebase `orders` (đơn mới hiện ngay, không cần làm mới).
///
/// LayoutBuilder: màn rộng (≥ 900) → 3 cột kiểu kanban; điện thoại → 3 tab có đếm số đơn.
class OrderBoardScreen extends StatefulWidget {
  const OrderBoardScreen({super.key, this.now});

  /// Đồng hồ (test truyền giờ cố định để kiểm tra nhãn "MỚI").
  final DateTime Function()? now;

  @override
  State<OrderBoardScreen> createState() => _OrderBoardScreenState();
}

class _OrderBoardScreenState extends State<OrderBoardScreen> {
  late Stream<List<OrderLive>> _board;
  final _search = TextEditingController();
  final Set<String> _busy = {};
  Set<String> _seen = {};
  bool _firstEvent = true;

  static const _columns = [OrderStatus.received, OrderStatus.cooking, OrderStatus.ready];

  @override
  void initState() {
    super.initState();
    _subscribe();
    _search.addListener(() => setState(() {}));
  }

  void _subscribe() {
    _board = context.read<RealtimeService>().watchBoard();
    _firstEvent = true;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();

  /// Có đơn mới (không phải lần tải đầu) → rung nhẹ để quầy để ý.
  void _notifyNewOrders(List<OrderLive> orders) {
    final ids = orders.map((o) => o.id).toSet();
    if (!_firstEvent && ids.difference(_seen).isNotEmpty) HapticFeedback.mediumImpact();
    _firstEvent = false;
    _seen = ids;
  }

  Future<void> _run(String orderId, Future<void> Function(StaffApi api) action, String done) async {
    final api = context.read<StaffApi>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(orderId));
    try {
      await action(api);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done), duration: const Duration(seconds: 2)));
    } on ApiException catch (e) {
      // 409 / INVALID_STATUS_TRANSITION: nhân viên khác vừa xử lý đơn này — bảng tự cập nhật qua Firebase.
      final msg = e.isConflict || e.code == 'INVALID_STATUS_TRANSITION'
          ? 'Đơn vừa được cập nhật ở máy khác. Bảng đã hiển thị trạng thái mới nhất.'
          : e.message;
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy.remove(orderId));
    }
  }

  void _advance(OrderLive o) {
    final step = BoardStep.of(o);
    if (step == null) return;
    _run(o.id, (api) => api.changeStatus(o.id, step.target), 'Đơn #${o.pickupCode}: ${step.target.label}');
  }

  Future<void> _confirmPayment(OrderLive o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xác nhận đã nhận ${Money.format(o.totalAmount)}?'),
        content: const Text(
          'Chỉ xác nhận khi đã thấy giao dịch chuyển khoản (ảnh chụp / sao kê) hoặc khách trả tiền mặt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Chưa')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đã nhận tiền')),
        ],
      ),
    );
    if (ok == true) await _run(o.id, (api) => api.confirmPayment(o.id), 'Đã ghi nhận thanh toán đơn #${o.pickupCode}');
  }

  Future<void> _cancel(OrderLive o) async {
    final reason = await TextPromptDialog.show(
      context,
      title: 'Hủy đơn #${o.pickupCode}?',
      label: 'Lý do (khách sẽ thấy)',
      minLength: 5,
      maxLength: 300,
      confirmLabel: 'Hủy đơn',
      suggestions: const ['Món đã hết', 'Khách không đến lấy', 'Quầy quá tải'],
    );
    if (reason != null) await _run(o.id, (api) => api.cancelOrder(o.id, reason), 'Đã hủy đơn #${o.pickupCode}');
  }

  List<OrderLive> _filter(List<OrderLive> all) {
    final q = _search.text.trim().toLowerCase().replaceAll('#', '');
    return all
        .where((o) => _columns.contains(o.status))
        .where(
          (o) =>
              q.isEmpty || o.pickupCode.toLowerCase().contains(q) || (o.customerName ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderLive>>(
      stream: _board,
      builder: (context, snapshot) {
        if (snapshot.hasData) _notifyNewOrders(snapshot.data!);
        final orders = _filter(snapshot.data ?? const []);
        final byStatus = {for (final s in _columns) s: orders.where((o) => o.status == s).toList()};

        Widget body;
        if (snapshot.hasError) {
          body = ErrorView(error: snapshot.error!, onRetry: () => setState(_subscribe));
        } else if (snapshot.connectionState == ConnectionState.waiting) {
          body = const SkeletonList();
        } else {
          body = LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in _columns)
                      Expanded(
                        child: _Column(status: s, orders: byStatus[s]!, card: _card, showHeader: true),
                      ),
                  ],
                );
              }
              return TabBarView(
                children: [for (final s in _columns) _Column(status: s, orders: byStatus[s]!, card: _card)],
              );
            },
          );
        }

        final wide = MediaQuery.sizeOf(context).width >= 900;
        return DefaultTabController(
          length: _columns.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Bảng đơn'),
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(wide ? 64 : 112),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
                      child: SizedBox(
                        height: kMinTapTarget,
                        child: TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            hintText: 'Tìm mã nhận món hoặc tên khách',
                            prefixIcon: const Icon(Icons.search_rounded),
                            contentPadding: EdgeInsets.zero,
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Xóa tìm kiếm',
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: _search.clear,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    if (!wide)
                      TabBar(tabs: [for (final s in _columns) Tab(text: '${s.label} (${byStatus[s]!.length})')]),
                  ],
                ),
              ),
            ),
            body: body,
          ),
        );
      },
    );
  }

  Widget _card(OrderLive o) => _OrderCard(
    order: o,
    isNew: o.status == OrderStatus.received && _now.difference(o.createdAt).inMinutes < 2,
    busy: _busy.contains(o.id),
    onAdvance: () => _advance(o),
    onConfirmPayment: () => _confirmPayment(o),
    onCancel: () => _cancel(o),
  );
}

class _Column extends StatelessWidget {
  const _Column({required this.status, required this.orders, required this.card, this.showHeader = false});

  final OrderStatus status;
  final List<OrderLive> orders;
  final Widget Function(OrderLive) card;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = StatusChip.colorOf(context, status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: Row(
              children: [
                Icon(StatusChip.iconOf(status), color: color),
                const SizedBox(width: AppSpacing.xs),
                Text('${status.label} (${orders.length})', style: theme.textTheme.titleMedium?.copyWith(color: color)),
              ],
            ),
          ),
        Expanded(
          child: orders.isEmpty
              ? EmptyState(
                  icon: StatusChip.iconOf(status),
                  title: switch (status) {
                    OrderStatus.received => 'Chưa có đơn mới',
                    OrderStatus.cooking => 'Không có món đang nấu',
                    _ => 'Không có món chờ giao',
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  itemCount: orders.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: card(orders[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.isNew,
    required this.busy,
    required this.onAdvance,
    required this.onConfirmPayment,
    required this.onCancel,
  });

  final OrderLive order;
  final bool isNew;
  final bool busy;
  final VoidCallback onAdvance;
  final VoidCallback onConfirmPayment;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final step = BoardStep.of(order);
    final waitingPay = BoardStep.waitingPayment(order);
    final canCancel = order.status == OrderStatus.received || order.status == OrderStatus.cooking;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(
          color: isNew ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
          width: isNew ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '#${order.pickupCode}',
                  style: theme.textTheme.titleMedium?.tabular.copyWith(color: theme.colorScheme.primary),
                ),
                if (isNew) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                    decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: AppRadius.smAll),
                    child: Text('MỚI', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white)),
                  ),
                ],
                const Spacer(),
                if (canCancel)
                  PopupMenuButton<String>(
                    tooltip: 'Thêm',
                    onSelected: (_) => onCancel(),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Hủy đơn'))],
                  ),
              ],
            ),
            Text(order.customerName ?? '', style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpacing.xs),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${item.quantity}× ', style: theme.textTheme.titleSmall),
                      TextSpan(text: item.name, style: theme.textTheme.bodyMedium),
                      if (item.options != null && item.options!.isNotEmpty)
                        TextSpan(text: ' · ${item.options}', style: muted),
                      if (item.note != null && item.note!.isNotEmpty)
                        TextSpan(
                          text: '\n  “${item.note}”',
                          style: muted?.copyWith(fontStyle: FontStyle.italic, color: colors.warning),
                        ),
                    ],
                  ),
                ),
              ),
            if (order.note != null && order.note!.isNotEmpty)
              Text('Ghi chú: ${order.note}', style: muted?.copyWith(color: colors.warning)),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    order.pickupTime != null
                        ? 'Hẹn ${VnTime.time(order.pickupTime!)} · đặt ${VnTime.time(order.createdAt)}'
                        : 'Lấy ngay · đặt ${VnTime.time(order.createdAt)}',
                    style: muted,
                  ),
                ),
                _PaymentBadge(order: order),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (waitingPay && order.status == OrderStatus.received) ...[
              Text(
                'Chờ khách chuyển khoản ${Money.format(order.totalAmount)} — chưa được nấu.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.warning),
              ),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton.icon(
                onPressed: busy ? null : onConfirmPayment,
                icon: const Icon(Icons.price_check_rounded),
                label: const Text('Xác nhận đã nhận tiền'),
              ),
            ] else if (step != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: StatusChip.colorOf(context, step.target)),
                onPressed: busy ? null : onAdvance,
                icon: busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Icon(step.icon),
                label: Text(step.label),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.order});

  final OrderLive order;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final paid = order.paymentStatus == PaymentStatus.paid;
    final (text, color) = switch (order.paymentMethod) {
      _ when paid => ('Đã trả ${Money.compact(order.totalAmount)}', colors.success),
      PaymentMethod.cash => ('Thu ${Money.format(order.totalAmount)}', colors.warning),
      PaymentMethod.bankTransfer => ('Chờ CK', colors.cancelled),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.smAll),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium?.tabular.copyWith(color: color)),
    );
  }
}
