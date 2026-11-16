import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/vn_time.dart';
import '../../data/local/order_dao.dart';
import '../../providers/home_tabs.dart';
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';

/// Tab Đơn hàng — lịch sử đơn "offline trước" (SQLite → API → SQLite), 3 tab theo trạng thái.
/// Đơn đang xử lý cập nhật trực tiếp từ Firebase (OrdersProvider nghe watchMyOrders).
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: OrderTab.values.length, vsync: this);
  final Set<OrderTab> _synced = {};

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _syncOnce(OrderTab.values[_tabs.index]);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOnce(OrderTab.active));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Mỗi tab đồng bộ với máy chủ một lần khi mở lần đầu (sau đó kéo để làm mới).
  void _syncOnce(OrderTab tab) {
    if (!mounted || !_synced.add(tab)) return;
    context.read<OrdersProvider>().refresh(tab);
  }

  Future<void> _confirmClear() async {
    final orders = context.read<OrdersProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa lịch sử đơn trên máy?'),
        content: const Text(
          'Hóa đơn lưu trên điện thoại sẽ bị xóa. Đơn trên hệ thống căn-tin vẫn còn và sẽ tải lại khi có mạng.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Giữ lại')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    final count = await orders.clearLocal();
    _synced.clear();
    messenger.showSnackBar(SnackBar(content: Text('Đã xóa $count hóa đơn khỏi máy.')));
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đơn hàng'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Tùy chọn',
            onSelected: (_) => _confirmClear(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('Xóa lịch sử trên máy'),
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [for (final tab in OrderTab.values) Tab(text: tab.label)],
        ),
      ),
      body: Column(
        children: [
          if (orders.isOffline) _OfflineBanner(onRetry: () => orders.refresh(OrderTab.values[_tabs.index])),
          if (orders.isSyncing) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [for (final tab in OrderTab.values) _OrderList(tab: tab)],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.warning;
    return Material(
      color: color.withValues(alpha: 0.12),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.cloud_off_rounded, color: color),
        title: const Text('Không có mạng — đang xem hóa đơn đã lưu trên máy'),
        trailing: TextButton(onPressed: onRetry, child: const Text('Thử lại')),
      ),
    );
  }
}

class _OrderList extends StatefulWidget {
  const _OrderList({required this.tab});

  final OrderTab tab;

  @override
  State<_OrderList> createState() => _OrderListState();
}

class _OrderListState extends State<_OrderList> with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) context.read<OrdersProvider>().loadMore(widget.tab);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _deleteLocal(LocalOrder order) async {
    final orders = context.read<OrdersProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xóa hóa đơn #${order.pickupCode} khỏi máy?'),
        content: const Text('Chỉ xóa bản lưu trên điện thoại.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true) await orders.deleteLocal(order.id);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<OrdersProvider>();
    final items = provider.ordersIn(widget.tab);

    if (!provider.isLoadedLocal) return const SkeletonList();
    if (items.isEmpty) {
      if (provider.isSyncing) return const SkeletonList();
      return RefreshIndicator(
        onRefresh: () => provider.refresh(widget.tab),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 420,
              child: provider.syncError != null && !provider.isOffline
                  ? ErrorView(error: provider.syncError!, onRetry: () => provider.refresh(widget.tab))
                  : EmptyState(
                      icon: widget.tab == OrderTab.active ? Icons.ramen_dining_outlined : Icons.receipt_long_outlined,
                      title: switch (widget.tab) {
                        OrderTab.active => 'Không có đơn đang xử lý',
                        OrderTab.completed => 'Chưa có đơn hoàn thành',
                        OrderTab.cancelled => 'Không có đơn đã hủy',
                      },
                      message: widget.tab == OrderTab.active ? 'Đói bụng rồi? Đặt món trước, đến quầy là có.' : null,
                      actionLabel: widget.tab == OrderTab.active ? 'Đặt món ngay' : null,
                      onAction: () => context.read<HomeTabs>().select(HomeTabs.menu),
                    ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.refresh(widget.tab),
      child: MaxWidthBox(
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: items.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: OrderCard(
              order: items[i],
              onTap: () => Navigator.pushNamed(context, AppRoutes.order, arguments: items[i].id),
              onDelete: widget.tab == OrderTab.active ? null : () => _deleteLocal(items[i]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thẻ một đơn trong lịch sử.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.onTap, this.onDelete});

  final LocalOrder order;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('#${order.pickupCode}', style: theme.textTheme.titleSmall),
                  const SizedBox(width: AppSpacing.xs),
                  StatusChip(order.status),
                  const SizedBox(width: AppSpacing.xs),
                  // Thời gian co lại (… cuối) trên màn hẹp thay vì làm tràn dòng.
                  Expanded(
                    child: Text(
                      VnTime.relative(order.createdAt),
                      style: muted,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(order.itemsPreview, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                    order.paymentStatus.name == 'paid' ? Icons.verified_rounded : Icons.payments_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(child: Text('${order.paymentMethod.label} · ${order.paymentStatus.label}', style: muted)),
                  PriceText(order.totalAmount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
