import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/money.dart';
import '../../core/utils/vn_time.dart';
import '../../data/firebase/realtime_service.dart';
import '../../data/local/order_dao.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/menu_api.dart';
import '../../data/remote/order_api.dart';
import '../../models/enums.dart';
import '../../models/live.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/home_tabs.dart';
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';
import 'reorder.dart';

/// Dữ liệu một đơn để hiển thị — từ máy chủ (đủ dòng thời gian, thanh toán) hoặc từ SQLite khi offline.
class OrderView {
  OrderView.fromDetail(OrderDetail d)
    : id = d.id,
      pickupCode = d.pickupCode,
      status = d.status,
      paymentMethod = d.paymentMethod,
      paymentStatus = d.paymentStatus,
      subtotal = d.subtotal,
      discountAmount = d.discountAmount,
      totalAmount = d.totalAmount,
      totalItems = d.totalItems,
      items = d.items,
      itemsPreview = d.itemsPreview,
      voucherCode = d.voucherCode,
      note = d.note,
      cancelReason = d.cancelReason,
      pickupTime = d.pickupTime,
      estimatedReadyAt = d.estimatedReadyAt,
      createdAt = d.createdAt,
      history = d.history,
      canCancel = d.canCancel,
      detail = d,
      isOffline = false;

  OrderView.fromLocal(LocalOrder o)
    : id = o.id,
      pickupCode = o.pickupCode,
      status = o.status,
      paymentMethod = o.paymentMethod,
      paymentStatus = o.paymentStatus,
      subtotal = o.subtotal,
      discountAmount = o.discountAmount,
      totalAmount = o.totalAmount,
      totalItems = o.totalItems,
      items = o.items,
      itemsPreview = o.itemsPreview,
      voucherCode = o.voucherCode,
      note = o.note,
      cancelReason = o.cancelReason,
      pickupTime = o.pickupTime,
      estimatedReadyAt = null,
      createdAt = o.createdAt,
      history = const [],
      canCancel = false,
      detail = null,
      isOffline = true;

  final String id;
  final String pickupCode;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final int subtotal;
  final int discountAmount;
  final int totalAmount;
  final int totalItems;
  final List<OrderItem> items;
  final String itemsPreview;
  final String? voucherCode;
  final String? note;
  final String? cancelReason;
  final DateTime? pickupTime;
  final DateTime? estimatedReadyAt;
  final DateTime createdAt;
  final List<OrderStatusEvent> history;
  final bool canCancel;

  /// Chi tiết đầy đủ từ máy chủ (null khi đang xem bản lưu offline).
  final OrderDetail? detail;
  final bool isOffline;
}

/// Theo dõi / chi tiết một đơn.
///
///  - FutureBuilder: chi tiết từ GET /api/orders/{id} (mất mạng → bản lưu SQLite).
///  - StreamBuilder: trạng thái realtime từ Firebase `orders/{id}` (RealtimeService.watchOrder — async*/yield).
///    Mỗi lần trạng thái đổi → ghi vào SQLite + tải lại chi tiết để có giờ của từng bước.
///  - OrientationBuilder: xoay ngang → trạng thái & mã nhận món bên trái, chi tiết bên phải.
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late final OrderApi _api = context.read<OrderApi>();
  late final OrderDao _dao = context.read<OrderDao>();
  late final OrdersProvider _orders = context.read<OrdersProvider>();
  late final String _uid = context.read<AuthProvider>().user!.uid;

  late Future<OrderView> _future;
  late final Stream<OrderLive?> _live;
  StreamSubscription<OrderLive?>? _liveSub;

  /// Trạng thái đã biết (từ lần tải gần nhất / sự kiện realtime trước) — để nhận ra thay đổi THẬT.
  OrderStatus? _knownStatus;
  PaymentStatus? _knownPayment;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // MỘT kết nối Firebase, phát cho hai nơi: StreamBuilder (vẽ) và listen (ghi SQLite).
    // Stream async* chỉ nghe được một lần → asBroadcastStream; giá trị gần nhất giữ trong [_latestLive]
    // làm initialData khi StreamBuilder được dựng lại.
    _live = context.read<RealtimeService>().watchOrder(widget.orderId).asBroadcastStream();
    _liveSub = _live.listen((live) {
      _latestLive = live;
      _onLive(live);
    }, onError: (_) {});
  }

  OrderLive? _latestLive;

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  Future<OrderView> _load() async {
    try {
      final detail = await _api.getOrder(widget.orderId);
      await _dao.upsertDetail(detail, _uid);
      unawaited(_orders.reloadLocal());
      _knownStatus = detail.status;
      _knownPayment = detail.paymentStatus;
      return OrderView.fromDetail(detail);
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final local = await _dao.getOrder(widget.orderId);
      if (local == null) rethrow;
      _knownStatus = local.status;
      _knownPayment = local.paymentStatus;
      return OrderView.fromLocal(local);
    }
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _onLive(OrderLive? live) async {
    if (live == null || !mounted) return;
    // So với dữ liệu đã tải: trùng → không làm gì; khác → căn-tin vừa đổi trạng thái.
    // (Chưa tải xong thì _knownStatus = null → bỏ qua; dữ liệu tải về đã là mới nhất.)
    if (_knownStatus == null) return;
    if (live.status == _knownStatus && live.paymentStatus == _knownPayment) return;
    _knownStatus = live.status;
    _knownPayment = live.paymentStatus;
    await _dao.updateStatus(
      live.id,
      status: live.status,
      paymentStatus: live.paymentStatus,
      cancelReason: live.cancelReason,
      updatedAt: live.updatedAt,
    );
    unawaited(_orders.reloadLocal());
    if (mounted) _reload(); // lấy giờ của bước mới cho dòng thời gian
  }

  Future<void> _cancel() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CancelSheet(),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final detail = await _api.cancel(widget.orderId, reason);
      await _dao.upsertDetail(detail, _uid);
      unawaited(_orders.reloadLocal());
      messenger.showSnackBar(const SnackBar(content: Text('Đã hủy đơn.')));
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorder(OrderView view) async {
    final messenger = ScaffoldMessenger.of(context);
    final tabs = context.read<HomeTabs>();
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final result = await reorder(view.items, menu: context.read<MenuApi>(), cart: context.read<CartProvider>());
    if (!mounted) return;
    setState(() => _busy = false);
    final skipped = result.skipped.isEmpty ? '' : ' Không thêm được: ${result.skipped.join(', ')}.';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.added == 0
              ? 'Các món trong đơn hiện không còn bán.$skipped'
              : 'Đã thêm ${result.added} món vào giỏ.$skipped',
        ),
      ),
    );
    if (result.added > 0) {
      tabs.select(HomeTabs.cart);
      navigator.popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OrderView>(
      future: _future,
      builder: (context, snapshot) {
        final view = snapshot.data;
        // Đang tải lại mà đã có dữ liệu cũ → vẫn hiển thị (không nháy màn hình chờ).
        if (view == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Đơn hàng')),
            body: switch (snapshot.connectionState) {
              ConnectionState.done when snapshot.hasError => ErrorView(error: snapshot.error!, onRetry: _reload),
              _ => const SkeletonList(itemCount: 4),
            },
          );
        }
        return StreamBuilder<OrderLive?>(
          stream: _live,
          initialData: _latestLive,
          builder: (context, liveSnap) => _OrderBody(
            view: view,
            live: liveSnap.data,
            isLive: liveSnap.hasData && liveSnap.data != null,
            busy: _busy,
            onRefresh: () async => _reload(),
            onCancel: _cancel,
            onReorder: () => _reorder(view),
          ),
        );
      },
    );
  }
}

class _OrderBody extends StatelessWidget {
  const _OrderBody({
    required this.view,
    required this.live,
    required this.isLive,
    required this.busy,
    required this.onRefresh,
    required this.onCancel,
    required this.onReorder,
  });

  final OrderView view;
  final OrderLive? live;
  final bool isLive;
  final bool busy;
  final Future<void> Function() onRefresh;
  final VoidCallback onCancel;
  final VoidCallback onReorder;

  // Trạng thái realtime (nếu có) được ưu tiên hơn dữ liệu đã tải.
  OrderStatus get status => live?.status ?? view.status;
  PaymentStatus get paymentStatus => live?.paymentStatus ?? view.paymentStatus;
  String? get cancelReason => live?.cancelReason ?? view.cancelReason;
  DateTime? get estimatedReadyAt => live?.estimatedReadyAt ?? view.estimatedReadyAt;

  bool get _awaitingTransfer =>
      status != OrderStatus.cancelled &&
      view.paymentMethod == PaymentMethod.bankTransfer &&
      paymentStatus == PaymentStatus.pending &&
      (view.detail?.payment?.qrCode != null);

  @override
  Widget build(BuildContext context) {
    final canCancel = status == OrderStatus.received && view.canCancel && !view.isOffline;
    final finished = status == OrderStatus.completed || status == OrderStatus.cancelled;

    final hero = _StatusHero(
      status: status,
      paymentStatus: paymentStatus,
      paymentMethod: view.paymentMethod,
      estimatedReadyAt: estimatedReadyAt,
      pickupTime: view.pickupTime,
      cancelReason: cancelReason,
      isLive: isLive,
    );
    final code = _PickupCodeCard(code: view.pickupCode, dimmed: finished);
    final timeline = _Timeline(status: status, history: view.history);
    final details = _Details(view: view, paymentStatus: paymentStatus);

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_awaitingTransfer)
          FilledButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.payment, arguments: view.detail),
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Thanh toán ngay'),
          ),
        if (status == OrderStatus.completed && !view.isOffline) ...[
          FilledButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.reviewOrder, arguments: view.id),
            icon: const Icon(Icons.star_rate_rounded),
            label: const Text('Đánh giá món'),
          ),
        ],
        if (finished && view.items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          (status == OrderStatus.completed ? OutlinedButton.icon : FilledButton.icon)(
            onPressed: busy ? null : onReorder,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Đặt lại'),
          ),
        ],
        if (canCancel) ...[
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: context.appColors.cancelled,
              side: BorderSide(color: context.appColors.cancelled.withValues(alpha: 0.4)),
            ),
            onPressed: busy ? null : onCancel,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Hủy đơn'),
          ),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Đơn #${view.pickupCode}'),
        bottom: busy
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final wide = orientation == Orientation.landscape || MediaQuery.sizeOf(context).width >= 840;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        hero,
                        const SizedBox(height: AppSpacing.md),
                        code,
                        const SizedBox(height: AppSpacing.md),
                        timeline,
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        details,
                        const SizedBox(height: AppSpacing.md),
                        actions,
                      ],
                    ),
                  ),
                ],
              );
            }
            return RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  MaxWidthBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (view.isOffline) ...[const _OfflineNote(), const SizedBox(height: AppSpacing.sm)],
                        hero,
                        const SizedBox(height: AppSpacing.md),
                        code,
                        const SizedBox(height: AppSpacing.md),
                        timeline,
                        const SizedBox(height: AppSpacing.md),
                        details,
                        const SizedBox(height: AppSpacing.md),
                        actions,
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.warning;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.mdAll),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: color, size: 20),
          const SizedBox(width: AppSpacing.xs),
          const Expanded(child: Text('Đang xem hóa đơn lưu trên máy (không có mạng).')),
        ],
      ),
    );
  }
}

/// Khối trạng thái đầu màn: biểu tượng + câu trạng thái tự tin + giờ dự kiến.
class _StatusHero extends StatelessWidget {
  const _StatusHero({
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.estimatedReadyAt,
    required this.pickupTime,
    required this.cancelReason,
    required this.isLive,
  });

  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final PaymentMethod paymentMethod;
  final DateTime? estimatedReadyAt;
  final DateTime? pickupTime;
  final String? cancelReason;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = StatusChip.colorOf(context, status);
    final waitingTransfer =
        status == OrderStatus.received &&
        paymentMethod == PaymentMethod.bankTransfer &&
        paymentStatus == PaymentStatus.pending;
    final subtitle = switch (status) {
      OrderStatus.cancelled => cancelReason ?? status.description,
      _ when waitingTransfer => 'Căn-tin sẽ bắt đầu nấu ngay khi nhận được tiền chuyển khoản.',
      OrderStatus.received || OrderStatus.cooking when pickupTime != null =>
        'Hẹn nhận lúc ${VnTime.time(pickupTime!)} — ${status.description.toLowerCase()}.',
      OrderStatus.received ||
      OrderStatus.cooking when estimatedReadyAt != null => 'Dự kiến xong khoảng ${VnTime.time(estimatedReadyAt!)}.',
      _ => status.description,
    };

    return AnimatedContainer(
      duration: AppDurations.slow,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.lgAll),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: AppDurations.normal,
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: Icon(StatusChip.iconOf(status), key: ValueKey(status), size: 40, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        waitingTransfer ? 'Chờ thanh toán' : status.label,
                        style: theme.textTheme.titleMedium?.copyWith(color: color),
                      ),
                    ),
                    if (isLive && status.isActive) ...[const SizedBox(width: AppSpacing.xs), const _LiveDot()],
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(subtitle, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chấm xanh nhấp nháy "Trực tiếp" — dữ liệu đang được cập nhật realtime.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.success;
    return Tooltip(
      message: 'Cập nhật trực tiếp',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text('Trực tiếp', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Mã nhận món cỡ lớn (FittedBox) — đưa cho quầy xem.
class _PickupCodeCard extends StatelessWidget {
  const _PickupCodeCard({required this.code, required this.dimmed});

  final String code;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Text(
              'Mã nhận món — đưa cho quầy',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(
              height: 64,
              child: FittedBox(
                child: Text(
                  code,
                  style: theme.textTheme.displaySmall?.tabular.copyWith(
                    fontSize: 48,
                    letterSpacing: 4,
                    color: dimmed ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
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

/// Dòng thời gian: Đã nhận → Đang nấu → Mời nhận món → Hoàn thành (kèm giờ từng bước nếu có).
class _Timeline extends StatelessWidget {
  const _Timeline({required this.status, required this.history});

  final OrderStatus status;
  final List<OrderStatusEvent> history;

  static const _steps = [OrderStatus.received, OrderStatus.cooking, OrderStatus.ready, OrderStatus.completed];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cancelled = status == OrderStatus.cancelled;
    final current = cancelled ? -1 : status.step;
    final muted = theme.colorScheme.onSurfaceVariant;

    DateTime? timeOf(OrderStatus s) => history.where((e) => e.toStatus == s).map((e) => e.changedAt).firstOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
        child: Column(
          children: [
            for (final (i, step) in _steps.indexed)
              Builder(
                builder: (context) {
                  final done = !cancelled && i <= current;
                  final isCurrent = !cancelled && i == current;
                  final color = done ? StatusChip.colorOf(context, step) : theme.colorScheme.outlineVariant;
                  final time = timeOf(step);
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 32,
                          child: Column(
                            children: [
                              AnimatedContainer(
                                duration: AppDurations.normal,
                                width: isCurrent ? 24 : 18,
                                height: isCurrent ? 24 : 18,
                                decoration: BoxDecoration(
                                  color: done ? color : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: color, width: 2),
                                ),
                                child: done ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                              ),
                              if (i < _steps.length - 1)
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    margin: const EdgeInsets.symmetric(vertical: 2),
                                    color: !cancelled && i < current ? color : theme.colorScheme.outlineVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    step.label,
                                    style: isCurrent
                                        ? theme.textTheme.titleSmall
                                        : theme.textTheme.bodyMedium?.copyWith(color: done ? null : muted),
                                  ),
                                ),
                                if (time != null)
                                  Text(
                                    VnTime.time(time),
                                    style: theme.textTheme.bodySmall?.tabular.copyWith(color: muted),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (cancelled)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.cancel_rounded, color: context.appColors.cancelled),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Đơn đã bị hủy',
                      style: theme.textTheme.titleSmall?.copyWith(color: context.appColors.cancelled),
                    ),
                    const Spacer(),
                    if (timeOf(OrderStatus.cancelled) case final t?)
                      Text(VnTime.time(t), style: theme.textTheme.bodySmall?.tabular.copyWith(color: muted)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Món, ghi chú, thanh toán, tổng tiền.
class _Details extends StatelessWidget {
  const _Details({required this.view, required this.paymentStatus});

  final OrderView view;
  final PaymentStatus paymentStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget row(String label, String value, {Color? color, bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Text(
            value,
            style: (strong ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)?.tabular.copyWith(color: color),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Món đã đặt', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            if (view.items.isEmpty)
              Text(view.itemsPreview, style: theme.textTheme.bodyMedium)
            else
              for (final item in view.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 32, child: Text('${item.quantity}×', style: theme.textTheme.titleSmall?.tabular)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.foodName, style: theme.textTheme.bodyMedium),
                            if (item.options.isNotEmpty) Text(item.optionsText, style: muted),
                            if (item.note != null && item.note!.isNotEmpty)
                              Text('“${item.note}”', style: muted?.copyWith(fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      Text(Money.format(item.lineTotal), style: theme.textTheme.bodyMedium?.tabular),
                    ],
                  ),
                ),
            if (view.note != null && view.note!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('Ghi chú: ${view.note}', style: muted),
            ],
            const Divider(height: AppSpacing.lg),
            if (view.subtotal > 0) row('Tạm tính', Money.format(view.subtotal)),
            if (view.discountAmount > 0)
              row(
                'Giảm giá${view.voucherCode != null ? ' (${view.voucherCode})' : ''}',
                Money.signed(-view.discountAmount),
                color: context.appColors.success,
              ),
            row('Tổng cộng', Money.format(view.totalAmount), color: context.appColors.price, strong: true),
            const SizedBox(height: AppSpacing.xs),
            row(
              view.paymentMethod.label,
              paymentStatus.label,
              color: paymentStatus == PaymentStatus.paid ? context.appColors.success : null,
            ),
            row('Đặt lúc', VnTime.dateTime(view.createdAt)),
          ],
        ),
      ),
    );
  }
}

/// Hủy đơn: chọn nhanh lý do hoặc tự nhập (5–300 ký tự — khớp backend).
class _CancelSheet extends StatefulWidget {
  const _CancelSheet();

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  static const _presets = ['Đặt nhầm món', 'Đổi ý, không ăn nữa', 'Không kịp đến lấy', 'Muốn đổi cách thanh toán'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Hủy đơn này?', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Chỉ hủy được khi căn-tin chưa bắt đầu nấu.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final p in _presets)
                  ActionChip(
                    label: Text(p),
                    onPressed: () => setState(() {
                      _controller.text = p;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _controller,
              maxLength: 300,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Lý do hủy'),
              validator: (v) {
                final len = v?.trim().length ?? 0;
                return len < 5 ? 'Lý do hủy cần ít nhất 5 ký tự.' : null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.appColors.cancelled),
              onPressed: () {
                if (_formKey.currentState!.validate()) Navigator.pop(context, _controller.text.trim());
              },
              child: const Text('Xác nhận hủy đơn'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Giữ đơn')),
          ],
        ),
      ),
    );
  }
}
