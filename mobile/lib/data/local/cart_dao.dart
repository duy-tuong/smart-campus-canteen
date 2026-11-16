import '../../models/cart_item.dart';
import 'database_helper.dart';

/// CRUD giỏ hàng trên SQLite (bảng cart_items + cart_item_options).
class CartDao {
  CartDao(this._helper);

  final DatabaseHelper _helper;

  /// Tối đa mỗi dòng (khớp CHECK của SQLite và giới hạn của backend).
  static const maxQuantity = 50;

  // ---------------------------- Read ----------------------------

  /// Giỏ hàng của một người dùng (kèm tùy chọn), cũ nhất trước — giữ đúng thứ tự đã thêm.
  Future<List<CartItem>> getItems(String userId) async {
    final db = await _helper.database;
    final rows = await db.query('cart_items', where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at, id');
    if (rows.isEmpty) return [];

    final ids = rows.map((r) => r['id'] as int).toList();
    final optionRows = await db.query(
      'cart_item_options',
      where: 'cart_item_id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
      orderBy: 'id',
    );
    final optionsByItem = <int, List<CartItemOption>>{};
    for (final o in optionRows) {
      optionsByItem.putIfAbsent(o['cart_item_id'] as int, () => []).add(CartItemOption.fromMap(o));
    }
    return rows.map((r) => CartItem.fromMap(r, optionsByItem[r['id']] ?? const [])).toList();
  }

  /// Tổng số món trong giỏ (badge trên thanh điều hướng).
  Future<int> countItems(String userId) async {
    final db = await _helper.database;
    final result = await db.rawQuery('SELECT COALESCE(SUM(quantity), 0) AS total FROM cart_items WHERE user_id = ?', [
      userId,
    ]);
    return (result.first['total'] as int?) ?? 0;
  }

  // ---------------------------- Create ----------------------------

  /// Thêm món vào giỏ. Nếu đã có dòng CÙNG món + cùng tùy chọn + cùng ghi chú thì cộng dồn số lượng
  /// (tối đa [maxQuantity]) thay vì tạo dòng mới. Trả về id của dòng.
  Future<int> add(CartItem item) async {
    final db = await _helper.database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'cart_items',
        columns: ['id', 'quantity'],
        where: 'user_id = ? AND food_id = ? AND options_key = ? AND note = ?',
        whereArgs: [item.userId, item.foodId, item.optionsKey, item.note ?? ''],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        final quantity = ((existing.first['quantity'] as int) + item.quantity).clamp(1, maxQuantity);
        await txn.update('cart_items', {'quantity': quantity}, where: 'id = ?', whereArgs: [id]);
        return id;
      }

      final id = await txn.insert('cart_items', item.toMap()..remove('id'));
      for (final option in item.options) {
        await txn.insert('cart_item_options', option.toMap(id));
      }
      return id;
    });
  }

  // ---------------------------- Update ----------------------------

  Future<void> updateQuantity(int id, int quantity) async {
    final db = await _helper.database;
    await db.update('cart_items', {'quantity': quantity.clamp(1, maxQuantity)}, where: 'id = ?', whereArgs: [id]);
  }

  /// Đổi ghi chú. Nếu ghi chú mới trùng với một dòng khác cùng món + tùy chọn → gộp hai dòng.
  Future<void> updateNote(int id, String? note) async {
    final db = await _helper.database;
    final value = note?.trim() ?? '';
    await db.transaction((txn) async {
      final current = (await txn.query('cart_items', where: 'id = ?', whereArgs: [id], limit: 1)).firstOrNull;
      if (current == null) return;

      final duplicate = (await txn.query(
        'cart_items',
        columns: ['id', 'quantity'],
        where: 'user_id = ? AND food_id = ? AND options_key = ? AND note = ? AND id <> ?',
        whereArgs: [current['user_id'], current['food_id'], current['options_key'], value, id],
        limit: 1,
      )).firstOrNull;

      if (duplicate == null) {
        await txn.update('cart_items', {'note': value}, where: 'id = ?', whereArgs: [id]);
        return;
      }
      final merged = ((duplicate['quantity'] as int) + (current['quantity'] as int)).clamp(1, maxQuantity);
      await txn.update('cart_items', {'quantity': merged}, where: 'id = ?', whereArgs: [duplicate['id']]);
      await txn.delete('cart_items', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------------------------- Delete ----------------------------

  /// Xóa một dòng (tùy chọn của dòng tự xóa theo nhờ ON DELETE CASCADE).
  Future<void> remove(int id) async {
    final db = await _helper.database;
    await db.delete('cart_items', where: 'id = ?', whereArgs: [id]);
  }

  /// Xóa sạch giỏ của người dùng (sau khi đặt món thành công).
  Future<void> clear(String userId) async {
    final db = await _helper.database;
    await db.delete('cart_items', where: 'user_id = ?', whereArgs: [userId]);
  }
}
