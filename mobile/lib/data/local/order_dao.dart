import 'package:sqflite/sqflite.dart';

import '../../models/enums.dart';
import '../../models/order.dart';
import 'database_helper.dart';

/// Hóa đơn lưu trên máy — đọc được khi không có mạng (màn Lịch sử đơn).
class LocalOrder {
  const LocalOrder({
    required this.id,
    required this.userId,
    required this.pickupCode,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.subtotal,
    required this.discountAmount,
    required this.totalAmount,
    required this.totalItems,
    required this.itemsPreview,
    required this.createdAt,
    required this.updatedAt,
    required this.syncedAt,
    this.items = const [],
    this.pickupDate,
    this.voucherCode,
    this.note,
    this.cancelReason,
    this.pickupTime,
  });

  final String id;
  final String userId;
  final String pickupCode;
  final String? pickupDate;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final int subtotal;
  final int discountAmount;
  final int totalAmount;
  final int totalItems;
  final String itemsPreview;
  final String? voucherCode;
  final String? note;
  final String? cancelReason;
  final DateTime? pickupTime;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Lần cuối dữ liệu được đồng bộ với máy chủ.
  final DateTime syncedAt;

  /// Rỗng nếu mới chỉ lưu tóm tắt (chưa mở chi tiết lúc có mạng).
  final List<OrderItem> items;

  bool get hasItems => items.isNotEmpty;
}

/// CRUD lịch sử đơn trên SQLite (orders 1──< order_items 1──< order_item_options).
class OrderDao {
  OrderDao(this._helper, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DatabaseHelper _helper;
  final DateTime Function() _clock;

  // ---------------------------- Create / Update (upsert) ----------------------------

  /// Lưu đầy đủ một đơn (kèm món, tùy chọn) — khi vừa đặt món hoặc mở chi tiết lúc có mạng.
  /// Đơn đã có thì ghi đè (món cũ được thay bằng danh sách mới).
  Future<void> upsertDetail(OrderDetail order, String userId) async {
    final db = await _helper.database;
    await db.transaction((txn) async {
      await txn.insert('orders', {
        ..._headerFromDetail(order, userId),
        'synced_at': _now(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // replace = xóa dòng cũ rồi chèn mới → món cũ đã bị CASCADE; chèn lại món hiện tại.
      for (final item in order.items) {
        final itemId = await txn.insert('order_items', {
          'order_id': order.id,
          'food_id': item.foodId,
          'food_name': item.foodName,
          'image_url': item.imageUrl,
          'unit_price': item.unitPrice,
          'options_price': item.optionsPrice,
          'quantity': item.quantity,
          'line_total': item.lineTotal,
          'note': item.note,
        });
        for (final option in item.options) {
          await txn.insert('order_item_options', {
            'order_item_id': itemId,
            'group_name': option.groupName,
            'option_name': option.optionName,
            'extra_price': option.extraPrice,
          });
        }
      }
    });
  }

  /// Lưu danh sách tóm tắt từ API (GET /api/orders/me). Chỉ cập nhật phần đầu đơn —
  /// KHÔNG xóa món đã lưu trước đó (dùng UPDATE thay vì REPLACE cho đơn đã có).
  Future<void> upsertSummaries(List<OrderSummary> orders, String userId) async {
    final db = await _helper.database;
    final now = _now();
    await db.transaction((txn) async {
      for (final o in orders) {
        final values = {
          'user_id': userId,
          'pickup_code': o.pickupCode,
          'status': o.status.name,
          'payment_method': o.paymentMethod.name,
          'payment_status': o.paymentStatus.name,
          'total_amount': o.totalAmount,
          'total_items': o.totalItems,
          'items_preview': o.itemsPreview,
          'pickup_time': o.pickupTime?.millisecondsSinceEpoch,
          'created_at': o.createdAt.millisecondsSinceEpoch,
          'synced_at': now,
        };
        final updated = await txn.update('orders', values, where: 'id = ?', whereArgs: [o.id]);
        if (updated == 0) {
          await txn.insert('orders', {...values, 'id': o.id, 'updated_at': o.createdAt.millisecondsSinceEpoch});
        }
      }
    });
  }

  /// Cập nhật trạng thái khi nhận thay đổi realtime từ Firebase (màn Theo dõi đơn).
  Future<bool> updateStatus(
    String id, {
    required OrderStatus status,
    PaymentStatus? paymentStatus,
    DateTime? updatedAt,
    String? cancelReason,
  }) async {
    final db = await _helper.database;
    final count = await db.update(
      'orders',
      {
        'status': status.name,
        'payment_status': ?paymentStatus?.name,
        'cancel_reason': ?cancelReason,
        'updated_at': (updatedAt ?? _clock()).millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }

  // ---------------------------- Read ----------------------------

  /// Danh sách đơn của tôi, mới nhất trước. Lọc theo trạng thái nếu cần.
  Future<List<LocalOrder>> getOrders(String userId, {Set<OrderStatus>? statuses, int? limit, int offset = 0}) async {
    final db = await _helper.database;
    final where = StringBuffer('user_id = ?');
    final args = <Object?>[userId];
    if (statuses != null && statuses.isNotEmpty) {
      where.write(' AND status IN (${List.filled(statuses.length, '?').join(',')})');
      args.addAll(statuses.map((s) => s.name));
    }
    final rows = await db.query('orders',
        where: where.toString(), whereArgs: args, orderBy: 'created_at DESC', limit: limit, offset: offset);
    return rows.map((r) => _fromRow(r, const [])).toList();
  }

  /// Chi tiết một đơn (kèm món + tùy chọn) — null nếu chưa lưu.
  Future<LocalOrder?> getOrder(String id) async {
    final db = await _helper.database;
    final rows = await db.query('orders', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;

    final itemRows = await db.query('order_items', where: 'order_id = ?', whereArgs: [id], orderBy: 'id');
    final items = <OrderItem>[];
    for (final row in itemRows) {
      final optionRows = await db.query('order_item_options', where: 'order_item_id = ?', whereArgs: [row['id']], orderBy: 'id');
      items.add(OrderItem(
        id: row['id'] as int,
        foodId: row['food_id'] as int?,
        foodName: row['food_name'] as String,
        imageUrl: row['image_url'] as String?,
        unitPrice: row['unit_price'] as int,
        optionsPrice: row['options_price'] as int,
        quantity: row['quantity'] as int,
        lineTotal: row['line_total'] as int,
        note: row['note'] as String?,
        options: optionRows
            .map((o) => OrderItemOption(
                  groupName: o['group_name'] as String,
                  optionName: o['option_name'] as String,
                  extraPrice: o['extra_price'] as int,
                ))
            .toList(),
      ));
    }
    return _fromRow(rows.first, items);
  }

  Future<int> count(String userId) async {
    final db = await _helper.database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM orders WHERE user_id = ?', [userId])) ?? 0;
  }

  // ---------------------------- Delete ----------------------------

  /// Xóa một hóa đơn khỏi máy (món + tùy chọn tự xóa theo CASCADE). Không ảnh hưởng dữ liệu trên máy chủ.
  Future<void> delete(String id) async {
    final db = await _helper.database;
    await db.delete('orders', where: 'id = ?', whereArgs: [id]);
  }

  /// Xóa toàn bộ lịch sử đơn của người dùng trên máy.
  Future<int> deleteAll(String userId) async {
    final db = await _helper.database;
    return db.delete('orders', where: 'user_id = ?', whereArgs: [userId]);
  }

  // ---------------------------- Hỗ trợ ----------------------------

  int _now() => _clock().millisecondsSinceEpoch;

  static Map<String, Object?> _headerFromDetail(OrderDetail o, String userId) => {
        'id': o.id,
        'user_id': userId,
        'pickup_code': o.pickupCode,
        'pickup_date': o.pickupDate,
        'status': o.status.name,
        'payment_method': o.paymentMethod.name,
        'payment_status': o.paymentStatus.name,
        'subtotal': o.subtotal,
        'discount_amount': o.discountAmount,
        'total_amount': o.totalAmount,
        'total_items': o.totalItems,
        'items_preview': o.itemsPreview,
        'voucher_code': o.voucherCode,
        'note': o.note,
        'cancel_reason': o.cancelReason,
        'pickup_time': o.pickupTime?.millisecondsSinceEpoch,
        'created_at': o.createdAt.millisecondsSinceEpoch,
        'updated_at': o.updatedAt.millisecondsSinceEpoch,
      };

  static DateTime _time(Object? ms) => DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);

  static LocalOrder _fromRow(Map<String, Object?> r, List<OrderItem> items) => LocalOrder(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        pickupCode: r['pickup_code'] as String,
        pickupDate: r['pickup_date'] as String?,
        status: OrderStatus.fromJson(r['status']),
        paymentMethod: PaymentMethod.fromJson(r['payment_method']),
        paymentStatus: PaymentStatus.fromJson(r['payment_status']),
        subtotal: r['subtotal'] as int,
        discountAmount: r['discount_amount'] as int,
        totalAmount: r['total_amount'] as int,
        totalItems: r['total_items'] as int,
        itemsPreview: r['items_preview'] as String,
        voucherCode: r['voucher_code'] as String?,
        note: r['note'] as String?,
        cancelReason: r['cancel_reason'] as String?,
        pickupTime: r['pickup_time'] == null ? null : _time(r['pickup_time']),
        createdAt: _time(r['created_at']),
        updatedAt: _time(r['updated_at']),
        syncedAt: _time(r['synced_at']),
        items: items,
      );
}
