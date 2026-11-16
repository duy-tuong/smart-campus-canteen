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

/// Hóa đơn lưu trong bộ nhớ (OrderDao thật đã kiểm tra riêng trên SQLite).
class MemoryOrderDao implements OrderDao {
  final Map<String, (OrderDetail, String)> saved = {};

  @override
  Future<void> upsertDetail(OrderDetail order, String userId) async => saved[order.id] = (order, userId);

  @override
  Future<void> upsertSummaries(List<OrderSummary> orders, String userId) async {}

  @override
  Future<bool> updateStatus(
    String id, {
    required OrderStatus status,
    PaymentStatus? paymentStatus,
    DateTime? updatedAt,
    String? cancelReason,
  }) async => saved.containsKey(id);

  @override
  Future<List<LocalOrder>> getOrders(String userId, {Set<OrderStatus>? statuses, int? limit, int offset = 0}) async =>
      const [];

  @override
  Future<LocalOrder?> getOrder(String id) async => null;

  @override
  Future<int> count(String userId) async => saved.values.where((e) => e.$2 == userId).length;

  @override
  Future<void> delete(String id) async => saved.remove(id);

  @override
  Future<int> deleteAll(String userId) async {
    final before = saved.length;
    saved.removeWhere((_, v) => v.$2 == userId);
    return before - saved.length;
  }
}
