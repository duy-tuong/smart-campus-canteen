import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/firebase/realtime_service.dart';
import '../data/local/order_dao.dart';
import '../data/remote/api_exception.dart';
import '../data/remote/order_api.dart';
import '../models/enums.dart';
import '../models/live.dart';

/// Ba tab của màn Đơn hàng — khớp tham số `status` của GET /api/orders/me.
enum OrderTab {
  active('active', 'Đang xử lý', {OrderStatus.received, OrderStatus.cooking, OrderStatus.ready}),
  completed('completed', 'Hoàn thành', {OrderStatus.completed}),
  cancelled('cancelled', 'Đã hủy', {OrderStatus.cancelled});

  const OrderTab(this.apiValue, this.label, this.statuses);
  final String apiValue;
  final String label;
  final Set<OrderStatus> statuses;
}

/// Lịch sử đơn — "offline trước":
///  1. Đọc SQLite → hiện ngay (kể cả khi không có mạng).
///  2. Gọi GET /api/orders/me → ghi đè vào SQLite → đọc lại.
///  3. Nghe Firebase (đơn đang xử lý) → trạng thái mới được ghi vào SQLite ngay lập tức.
/// Mất mạng → giữ dữ liệu trên máy + cờ [isOffline] để màn hình hiện banner.
class OrdersProvider extends ChangeNotifier {
  OrdersProvider({required this.api, required this.dao, required this.realtime});

  final OrderApi api;
  final OrderDao dao;
  final RealtimeService realtime;

  String? _userId;
  List<LocalOrder> _orders = const [];
  bool _loadedLocal = false;
  bool _syncing = false;
  bool _isOffline = false;
  Object? _syncError;
  final Map<OrderTab, int> _pages = {};
  final Map<OrderTab, bool> _hasMore = {};
  StreamSubscription<List<OrderLive>>? _liveSub;
  int _generation = 0;

  String? get userId => _userId;
  bool get isLoadedLocal => _loadedLocal;
  bool get isSyncing => _syncing;
  bool get isOffline => _isOffline;
  Object? get syncError => _syncError;

  List<LocalOrder> ordersIn(OrderTab tab) => _orders.where((o) => tab.statuses.contains(o.status)).toList();
  bool hasMore(OrderTab tab) => _hasMore[tab] ?? true;

  /// Đổi người dùng (gọi từ ChangeNotifierProxyProvider — không notify đồng bộ).
  void attachUser(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _generation++;
    _orders = const [];
    _loadedLocal = false;
    _isOffline = false;
    _syncError = null;
    _pages.clear();
    _hasMore.clear();
    _liveSub?.cancel();
    _liveSub = null;
    if (userId == null) return;
    final generation = _generation;
    Future.microtask(() async {
      await _reloadLocal(generation);
      if (generation != _generation) return;
      // Nghe đơn đang xử lý trên Firebase → cập nhật SQLite ngay khi căn-tin đổi trạng thái.
      _liveSub = realtime.watchMyOrders(userId).listen(applyLive, onError: (_) {});
    });
  }

  Future<void> _reloadLocal([int? generation]) async {
    final uid = _userId;
    if (uid == null) return;
    final orders = await dao.getOrders(uid);
    if (generation != null && generation != _generation) return;
    _orders = orders;
    _loadedLocal = true;
    notifyListeners();
  }

  /// Đồng bộ trang 1 của một tab với máy chủ (kéo để làm mới / mở tab).
  Future<void> refresh(OrderTab tab) => _sync(tab, page: 1);

  /// Tải thêm trang kế tiếp từ máy chủ (cuộn gần cuối danh sách).
  Future<void> loadMore(OrderTab tab) async {
    if (_syncing || !hasMore(tab) || _isOffline) return;
    await _sync(tab, page: (_pages[tab] ?? 0) + 1);
  }

  Future<void> _sync(OrderTab tab, {required int page}) async {
    final uid = _userId;
    if (uid == null) return;
    final generation = _generation;
    _syncing = true;
    notifyListeners();
    try {
      final result = await api.myOrders(status: tab.apiValue, page: page);
      if (generation != _generation) return;
      await dao.upsertSummaries(result.items, uid);
      _pages[tab] = page;
      _hasMore[tab] = result.hasNext;
      _isOffline = false;
      _syncError = null;
      await _reloadLocal(generation);
    } on ApiException catch (e) {
      if (generation != _generation) return;
      _isOffline = e.isNetwork;
      _syncError = e;
    } finally {
      if (generation == _generation) {
        _syncing = false;
        notifyListeners();
      }
    }
  }

  /// Trạng thái mới từ Firebase → ghi vào SQLite + cập nhật danh sách đang hiển thị.
  Future<void> applyLive(List<OrderLive> live) async {
    var changed = false;
    for (final l in live) {
      final local = _orders.where((o) => o.id == l.id).firstOrNull;
      if (local == null) continue; // đơn chưa có trên máy → lần đồng bộ sau sẽ tải về
      if (local.status == l.status && local.paymentStatus == l.paymentStatus) continue;
      await dao.updateStatus(
        l.id,
        status: l.status,
        paymentStatus: l.paymentStatus,
        cancelReason: l.cancelReason,
        updatedAt: l.updatedAt,
      );
      changed = true;
    }
    if (changed) await _reloadLocal();
  }

  /// Xóa một hóa đơn khỏi máy (không ảnh hưởng máy chủ).
  Future<void> deleteLocal(String id) async {
    await dao.delete(id);
    await _reloadLocal();
  }

  /// Xóa toàn bộ lịch sử đơn trên máy.
  Future<int> clearLocal() async {
    final uid = _userId;
    if (uid == null) return 0;
    final count = await dao.deleteAll(uid);
    _pages.clear();
    _hasMore.clear();
    await _reloadLocal();
    return count;
  }

  /// Ghi nhận đơn vừa thay đổi ở màn khác (đặt món, hủy đơn, xem chi tiết).
  Future<void> reloadLocal() => _reloadLocal();

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }
}
