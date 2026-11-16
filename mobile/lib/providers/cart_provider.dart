import 'package:flutter/foundation.dart';

import '../data/local/cart_dao.dart';
import '../models/cart_item.dart';
import '../models/menu.dart';

/// Giỏ hàng của người đang đăng nhập — lưu SQLite (CartDao) nên còn nguyên khi tắt/mở lại app.
/// Mỗi tài khoản một giỏ riêng.
class CartProvider extends ChangeNotifier {
  CartProvider(this._dao, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final CartDao _dao;
  final DateTime Function() _clock;

  String? _userId;
  List<CartItem> _items = const [];
  bool _loaded = false;

  /// Tăng khi đổi người dùng — kết quả đọc SQLite của người cũ về muộn bị bỏ qua.
  int _generation = 0;

  List<CartItem> get items => _items;
  bool get isLoaded => _loaded;
  bool get isEmpty => _items.isEmpty;
  String? get userId => _userId;

  /// Tổng số phần (badge trên thanh điều hướng).
  int get totalQuantity => _items.fold(0, (sum, i) => sum + i.quantity);

  /// Tạm tính (giá hiển thị; server tính lại khi đặt món).
  int get subtotal => _items.fold(0, (sum, i) => sum + i.lineTotal);

  /// Số phần của một món (mọi cấu hình tùy chọn) đang có trong giỏ.
  int quantityOf(int foodId) => _items.where((i) => i.foodId == foodId).fold(0, (sum, i) => sum + i.quantity);

  /// Gọi từ ChangeNotifierProxyProvider khi phiên đăng nhập đổi — không notify đồng bộ (đang trong build).
  void attachUser(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _items = const [];
    _loaded = false;
    final generation = ++_generation;
    if (userId != null) Future.microtask(() => _reload(generation));
  }

  Future<void> reload() => _reload(_generation);

  Future<void> _reload(int generation) async {
    final userId = _userId;
    if (userId == null) return;
    final items = await _dao.getItems(userId);
    if (generation != _generation) return;
    _items = items;
    _loaded = true;
    notifyListeners();
  }

  /// Thêm món (gộp với dòng trùng món + tùy chọn + ghi chú).
  Future<void> addFood(
    FoodSummary food, {
    int quantity = 1,
    List<CartItemOption> options = const [],
    String? note,
  }) async {
    final userId = _requireUser();
    final trimmed = note?.trim();
    await _dao.add(
      CartItem(
        userId: userId,
        foodId: food.id,
        foodName: food.name,
        imageUrl: food.imageUrl,
        unitPrice: food.price,
        quantity: quantity,
        note: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
        createdAt: _clock().toUtc(),
        options: options,
      ),
    );
    await reload();
  }

  Future<void> updateQuantity(int itemId, int quantity) async {
    await _dao.updateQuantity(itemId, quantity);
    await reload();
  }

  Future<void> updateNote(int itemId, String? note) async {
    await _dao.updateNote(itemId, note);
    await reload();
  }

  /// Xóa một dòng; trả về dòng đã xóa để có thể Hoàn tác.
  Future<CartItem?> remove(int itemId) async {
    final removed = _items.where((i) => i.id == itemId).firstOrNull;
    await _dao.remove(itemId);
    await reload();
    return removed;
  }

  /// Hoàn tác xóa: thêm lại đúng dòng cũ (giữ thời điểm thêm để về đúng vị trí).
  Future<void> restore(CartItem item) async {
    await _dao.add(item);
    await reload();
  }

  Future<void> clear() async {
    await _dao.clear(_requireUser());
    await reload();
  }

  String _requireUser() {
    final id = _userId;
    if (id == null) throw StateError('Chưa đăng nhập');
    return id;
  }
}
