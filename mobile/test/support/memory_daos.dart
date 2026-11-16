import 'package:campus_canteen/data/local/cart_dao.dart';
import 'package:campus_canteen/data/local/order_dao.dart';
import 'package:campus_canteen/data/local/search_history_dao.dart';
import 'package:campus_canteen/models/cart_item.dart';
import 'package:campus_canteen/models/enums.dart';
import 'package:campus_canteen/models/order.dart';

/// Giỏ hàng trong bộ nhớ cho test giao diện (cùng quy tắc gộp dòng với CartDao thật —
/// CartDao thật đã được kiểm tra riêng trên SQLite ở test/data/local_db_test.dart).
/// testWidgets chạy trong thời gian giả nên không đợi được I/O thật của SQLite.
class MemoryCartDao implements CartDao {
  final List<CartItem> rows = [];
  int _nextId = 1;

  @override
  Future<List<CartItem>> getItems(String userId) async => rows.where((r) => r.userId == userId).toList();

  @override
  Future<int> countItems(String userId) async =>
      rows.where((r) => r.userId == userId).fold<int>(0, (sum, r) => sum + r.quantity);

  @override
  Future<int> add(CartItem item) async {
    final index = rows.indexWhere(
      (r) =>
          r.userId == item.userId && r.foodId == item.foodId && r.optionsKey == item.optionsKey && r.note == item.note,
    );
    if (index >= 0) {
      final merged = (rows[index].quantity + item.quantity).clamp(1, CartDao.maxQuantity);
      rows[index] = rows[index].copyWith(quantity: merged);
      return rows[index].id!;
    }
    final id = _nextId++;
    rows.add(item.copyWith(id: id));
    return id;
  }

  @override
  Future<void> updateQuantity(int id, int quantity) async {
    final i = rows.indexWhere((r) => r.id == id);
    if (i >= 0) rows[i] = rows[i].copyWith(quantity: quantity.clamp(1, CartDao.maxQuantity));
  }

  @override
  Future<void> updateNote(int id, String? note) async {
    final i = rows.indexWhere((r) => r.id == id);
    if (i >= 0) rows[i] = rows[i].copyWith(note: note);
  }

  @override
  Future<void> remove(int id) async => rows.removeWhere((r) => r.id == id);

  @override
  Future<void> clear(String userId) async => rows.removeWhere((r) => r.userId == userId);
}

class MemorySearchHistoryDao implements SearchHistoryDao {
  final Map<String, List<String>> _byUser = {};

  @override
  Future<void> add(String userId, String keyword) async {
    final value = keyword.trim();
    if (value.isEmpty) return;
    final list = _byUser.putIfAbsent(userId, () => [])
      ..remove(value)
      ..insert(0, value);
    if (list.length > SearchHistoryDao.maxEntries) list.removeLast();
  }

  @override
  Future<List<String>> recent(String userId, {int limit = 8}) async =>
      (_byUser[userId] ?? const []).take(limit).toList();

  @override
  Future<void> remove(String userId, String keyword) async => _byUser[userId]?.remove(keyword.trim());

  @override
  Future<void> clear(String userId) async => _byUser.remove(userId);
}

/// Hóa đơn lưu trong bộ nhớ — cùng hành vi với OrderDao (OrderDao thật đã kiểm tra riêng trên SQLite):
/// tóm tắt không xóa món đã lưu, cập nhật trạng thái, lọc theo trạng thái, mới nhất trước.
class MemoryOrderDao implements OrderDao {
  final Map<String, LocalOrder> rows = {};

  static LocalOrder _fromDetail(OrderDetail o, String userId) => LocalOrder(
    id: o.id,
    userId: userId,
    pickupCode: o.pickupCode,
    pickupDate: o.pickupDate,
    status: o.status,
    paymentMethod: o.paymentMethod,
    paymentStatus: o.paymentStatus,
    subtotal: o.subtotal,
    discountAmount: o.discountAmount,
    totalAmount: o.totalAmount,
    totalItems: o.totalItems,
    itemsPreview: o.itemsPreview,
    voucherCode: o.voucherCode,
    note: o.note,
    cancelReason: o.cancelReason,
    pickupTime: o.pickupTime,
    createdAt: o.createdAt,
    updatedAt: o.updatedAt,
    syncedAt: DateTime.utc(2026, 11, 16),
    items: o.items,
  );

  @override
  Future<void> upsertDetail(OrderDetail order, String userId) async => rows[order.id] = _fromDetail(order, userId);

  @override
  Future<void> upsertSummaries(List<OrderSummary> orders, String userId) async {
    for (final o in orders) {
      final old = rows[o.id];
      rows[o.id] = LocalOrder(
        id: o.id,
        userId: userId,
        pickupCode: o.pickupCode,
        pickupDate: old?.pickupDate,
        status: o.status,
        paymentMethod: o.paymentMethod,
        paymentStatus: o.paymentStatus,
        subtotal: old?.subtotal ?? 0,
        discountAmount: old?.discountAmount ?? 0,
        totalAmount: o.totalAmount,
        totalItems: o.totalItems,
        itemsPreview: o.itemsPreview,
        voucherCode: old?.voucherCode,
        note: old?.note,
        cancelReason: old?.cancelReason,
        pickupTime: o.pickupTime,
        createdAt: o.createdAt,
        updatedAt: old?.updatedAt ?? o.createdAt,
        syncedAt: DateTime.utc(2026, 11, 16),
        items: old?.items ?? const [],
      );
    }
  }

  @override
  Future<bool> updateStatus(
    String id, {
    required OrderStatus status,
    PaymentStatus? paymentStatus,
    DateTime? updatedAt,
    String? cancelReason,
  }) async {
    final o = rows[id];
    if (o == null) return false;
    rows[id] = LocalOrder(
      id: o.id,
      userId: o.userId,
      pickupCode: o.pickupCode,
      pickupDate: o.pickupDate,
      status: status,
      paymentMethod: o.paymentMethod,
      paymentStatus: paymentStatus ?? o.paymentStatus,
      subtotal: o.subtotal,
      discountAmount: o.discountAmount,
      totalAmount: o.totalAmount,
      totalItems: o.totalItems,
      itemsPreview: o.itemsPreview,
      voucherCode: o.voucherCode,
      note: o.note,
      cancelReason: cancelReason ?? o.cancelReason,
      pickupTime: o.pickupTime,
      createdAt: o.createdAt,
      updatedAt: updatedAt ?? o.updatedAt,
      syncedAt: o.syncedAt,
      items: o.items,
    );
    return true;
  }

  @override
  Future<List<LocalOrder>> getOrders(String userId, {Set<OrderStatus>? statuses, int? limit, int offset = 0}) async {
    final list =
        rows.values
            .where((o) => o.userId == userId && (statuses == null || statuses.contains(o.status)))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.skip(offset).take(limit ?? list.length).toList();
  }

  @override
  Future<LocalOrder?> getOrder(String id) async => rows[id];

  @override
  Future<int> count(String userId) async => rows.values.where((o) => o.userId == userId).length;

  @override
  Future<void> delete(String id) async => rows.remove(id);

  @override
  Future<int> deleteAll(String userId) async {
    final before = rows.length;
    rows.removeWhere((_, o) => o.userId == userId);
    return before - rows.length;
  }
}
