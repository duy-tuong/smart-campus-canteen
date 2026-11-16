import 'package:campus_canteen/data/local/cart_dao.dart';
import 'package:campus_canteen/data/local/database_helper.dart';
import 'package:campus_canteen/data/local/order_dao.dart';
import 'package:campus_canteen/data/local/search_history_dao.dart';
import 'package:campus_canteen/models/cart_item.dart';
import 'package:campus_canteen/models/enums.dart';
import 'package:campus_canteen/models/order.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Kiểm tra CRUD cả 6 bảng SQLite trên CSDL trong bộ nhớ (sqflite_common_ffi).
void main() {
  sqfliteFfiInit();

  late DatabaseHelper helper;
  setUp(() => helper = DatabaseHelper(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  tearDown(() => helper.close());

  Future<int> countRows(String table) async =>
      Sqflite.firstIntValue(await (await helper.database).rawQuery('SELECT COUNT(*) FROM $table')) ?? 0;

  CartItem cartItem({String user = 'u1', int foodId = 1, int quantity = 1, String? note, List<CartItemOption> options = const []}) =>
      CartItem(
        userId: user,
        foodId: foodId,
        foodName: 'Trà sữa',
        unitPrice: 25000,
        quantity: quantity,
        note: note,
        createdAt: DateTime.utc(2026, 11, 16, 3),
        options: options,
      );

  const sizeL = CartItemOption(optionId: 12, groupName: 'Size', optionName: 'L', extraPrice: 5000);
  const pudding = CartItemOption(optionId: 15, groupName: 'Topping', optionName: 'Pudding', extraPrice: 7000);

  group('CartDao', () {
    test('thêm và đọc giỏ kèm tùy chọn, tính tiền đúng', () async {
      final dao = CartDao(helper);
      await dao.add(cartItem(quantity: 2, options: const [sizeL, pudding]));

      final items = await dao.getItems('u1');
      expect(items, hasLength(1));
      expect(items.single.options.map((o) => o.optionName), ['L', 'Pudding']);
      expect(items.single.optionsKey, '12,15');
      expect(items.single.lineTotal, (25000 + 12000) * 2);
      expect(items.single.note, isNull);
      expect(await dao.countItems('u1'), 2);
    });

    test('cùng món + cùng tùy chọn (khác thứ tự) + cùng ghi chú → gộp dòng, tối đa 50', () async {
      final dao = CartDao(helper);
      await dao.add(cartItem(quantity: 30, options: const [sizeL, pudding]));
      await dao.add(cartItem(quantity: 30, options: const [pudding, sizeL]));

      final items = await dao.getItems('u1');
      expect(items, hasLength(1));
      expect(items.single.quantity, CartDao.maxQuantity);
      expect(await countRows('cart_item_options'), 2, reason: 'không nhân đôi tùy chọn khi gộp');
    });

    test('khác ghi chú hoặc khác tùy chọn → dòng riêng', () async {
      final dao = CartDao(helper);
      await dao.add(cartItem());
      await dao.add(cartItem(note: 'Ít đá'));
      await dao.add(cartItem(options: const [sizeL]));
      expect(await dao.getItems('u1'), hasLength(3));
    });

    test('giỏ hàng tách riêng theo người dùng', () async {
      final dao = CartDao(helper);
      await dao.add(cartItem(user: 'u1'));
      await dao.add(cartItem(user: 'u2', quantity: 3));
      expect(await dao.countItems('u1'), 1);
      expect(await dao.countItems('u2'), 3);
    });

    test('cập nhật số lượng (giới hạn 1–50) và ghi chú (gộp khi trùng)', () async {
      final dao = CartDao(helper);
      final a = await dao.add(cartItem(quantity: 2));
      final b = await dao.add(cartItem(quantity: 3, note: 'Ít đá'));

      await dao.updateQuantity(a, 99);
      expect((await dao.getItems('u1')).firstWhere((i) => i.id == a).quantity, 50);
      await dao.updateQuantity(a, 4);

      await dao.updateNote(b, '  '); // ghi chú rỗng → trùng dòng a → gộp
      final items = await dao.getItems('u1');
      expect(items, hasLength(1));
      expect(items.single.id, a);
      expect(items.single.quantity, 7);
    });

    test('xóa một dòng → tùy chọn tự xóa theo (CASCADE); xóa sạch giỏ', () async {
      final dao = CartDao(helper);
      final id = await dao.add(cartItem(options: const [sizeL, pudding]));
      await dao.add(cartItem(foodId: 2));

      await dao.remove(id);
      expect(await countRows('cart_item_options'), 0);
      expect(await dao.getItems('u1'), hasLength(1));

      await dao.clear('u1');
      expect(await dao.getItems('u1'), isEmpty);
    });
  });

  group('OrderDao', () {
    OrderDetail detail({String id = 'o1', OrderStatus status = OrderStatus.received, int itemCount = 2}) => OrderDetail(
          id: id,
          pickupCode: 'A012',
          pickupDate: '2026-11-16',
          status: status,
          paymentMethod: PaymentMethod.cash,
          paymentStatus: PaymentStatus.pending,
          subtotal: 60000,
          discountAmount: 5000,
          totalAmount: 55000,
          totalItems: itemCount,
          createdAt: DateTime.utc(2026, 11, 16, 3, 0),
          updatedAt: DateTime.utc(2026, 11, 16, 3, 0),
          customer: const OrderCustomer(id: 'u1', fullName: 'Sinh viên 1'),
          items: [
            for (var i = 0; i < itemCount; i++)
              OrderItem(
                foodId: i + 1,
                foodName: 'Món $i',
                unitPrice: 25000,
                optionsPrice: 5000,
                quantity: 1,
                lineTotal: 30000,
                options: const [OrderItemOption(groupName: 'Size', optionName: 'L', extraPrice: 5000)],
              ),
          ],
          history: const [],
          canCancel: true,
          allowedNextStatuses: const [],
          voucherCode: 'GIAM5K',
        );

    test('lưu chi tiết đơn và đọc lại đầy đủ (offline)', () async {
      final dao = OrderDao(helper);
      await dao.upsertDetail(detail(), 'u1');

      final order = await dao.getOrder('o1');
      expect(order, isNotNull);
      expect(order!.pickupCode, 'A012');
      expect(order.voucherCode, 'GIAM5K');
      expect(order.items, hasLength(2));
      expect(order.items.first.options.single.optionName, 'L');
      expect(order.itemsPreview, 'Món 0 ×1, Món 1 ×1');
      expect(order.createdAt, DateTime.utc(2026, 11, 16, 3, 0));
    });

    test('lưu lại cùng đơn → thay món cũ, không nhân đôi', () async {
      final dao = OrderDao(helper);
      await dao.upsertDetail(detail(itemCount: 3), 'u1');
      await dao.upsertDetail(detail(itemCount: 1), 'u1');

      expect((await dao.getOrder('o1'))!.items, hasLength(1));
      expect(await countRows('order_items'), 1);
      expect(await countRows('order_item_options'), 1);
    });

    test('lưu danh sách tóm tắt không xóa món đã lưu', () async {
      final dao = OrderDao(helper);
      await dao.upsertDetail(detail(), 'u1');
      await dao.upsertSummaries([
        OrderSummary(
          id: 'o1',
          pickupCode: 'A012',
          status: OrderStatus.cooking,
          paymentMethod: PaymentMethod.cash,
          paymentStatus: PaymentStatus.pending,
          totalAmount: 55000,
          totalItems: 2,
          itemsPreview: 'Món 0 ×1, Món 1 ×1',
          customerName: 'Sinh viên 1',
          createdAt: DateTime.utc(2026, 11, 16, 3, 0),
        ),
        OrderSummary(
          id: 'o2',
          pickupCode: 'A013',
          status: OrderStatus.completed,
          paymentMethod: PaymentMethod.bankTransfer,
          paymentStatus: PaymentStatus.paid,
          totalAmount: 8000,
          totalItems: 1,
          itemsPreview: 'Nước suối ×1',
          customerName: 'Sinh viên 1',
          createdAt: DateTime.utc(2026, 11, 16, 4, 0),
        ),
      ], 'u1');

      final o1 = await dao.getOrder('o1');
      expect(o1!.status, OrderStatus.cooking);
      expect(o1.items, hasLength(2));
      expect(o1.subtotal, 60000, reason: 'giữ cột chỉ có trong chi tiết');

      final o2 = await dao.getOrder('o2');
      expect(o2!.hasItems, isFalse);
      expect(o2.paymentMethod, PaymentMethod.bankTransfer);
    });

    test('đọc danh sách: mới nhất trước, lọc theo trạng thái, theo người dùng', () async {
      final dao = OrderDao(helper);
      await dao.upsertDetail(detail(id: 'old', status: OrderStatus.completed), 'u1');
      await dao.upsertSummaries([
        OrderSummary(
          id: 'new',
          pickupCode: 'B001',
          status: OrderStatus.cooking,
          paymentMethod: PaymentMethod.cash,
          paymentStatus: PaymentStatus.pending,
          totalAmount: 1000,
          totalItems: 1,
          itemsPreview: '',
          customerName: '',
          createdAt: DateTime.utc(2026, 11, 17),
        ),
      ], 'u1');
      await dao.upsertDetail(detail(id: 'other'), 'u2');

      expect((await dao.getOrders('u1')).map((o) => o.id), ['new', 'old']);
      expect((await dao.getOrders('u1', statuses: {OrderStatus.completed})).map((o) => o.id), ['old']);
      expect(await dao.count('u1'), 2);
    });

    test('cập nhật trạng thái từ realtime', () async {
      final dao = OrderDao(helper);
      await dao.upsertDetail(detail(), 'u1');

      final ok = await dao.updateStatus('o1',
          status: OrderStatus.cancelled, paymentStatus: PaymentStatus.failed, cancelReason: 'Hết món', updatedAt: DateTime.utc(2026, 11, 16, 5));
      expect(ok, isTrue);
      final order = await dao.getOrder('o1');
      expect(order!.status, OrderStatus.cancelled);
      expect(order.paymentStatus, PaymentStatus.failed);
      expect(order.cancelReason, 'Hết món');
      expect(order.updatedAt, DateTime.utc(2026, 11, 16, 5));

      expect(await dao.updateStatus('missing', status: OrderStatus.ready), isFalse);
    });

    test('xóa một đơn → món và tùy chọn xóa theo (CASCADE); xóa toàn bộ lịch sử', () async {
      final dao = OrderDao(helper);
      await dao.upsertDetail(detail(id: 'o1'), 'u1');
      await dao.upsertDetail(detail(id: 'o2'), 'u1');

      await dao.delete('o1');
      expect(await dao.getOrder('o1'), isNull);
      expect(await countRows('order_items'), 2);
      expect(await countRows('order_item_options'), 2);

      expect(await dao.deleteAll('u1'), 1);
      expect(await countRows('order_items'), 0);
      expect(await countRows('order_item_options'), 0);
    });
  });

  group('SearchHistoryDao', () {
    test('lưu, tìm lại thì đưa lên đầu, bỏ từ rỗng', () async {
      var now = DateTime.utc(2026, 11, 16);
      final dao = SearchHistoryDao(helper, clock: () => now = now.add(const Duration(seconds: 1)));
      await dao.add('u1', 'com ga');
      await dao.add('u1', 'tra sua');
      await dao.add('u1', '  com ga  ');
      await dao.add('u1', '   ');

      expect(await dao.recent('u1'), ['com ga', 'tra sua']);
      expect(await countRows('search_history'), 2);
    });

    test('giữ tối đa 20 từ khóa mỗi người', () async {
      var now = DateTime.utc(2026, 11, 16);
      final dao = SearchHistoryDao(helper, clock: () => now = now.add(const Duration(seconds: 1)));
      for (var i = 0; i < 25; i++) {
        await dao.add('u1', 'kw$i');
      }
      await dao.add('u2', 'khac');

      final all = await dao.recent('u1', limit: 100);
      expect(all, hasLength(SearchHistoryDao.maxEntries));
      expect(all.first, 'kw24');
      expect(all.last, 'kw5');
      expect(await dao.recent('u2'), ['khac']);
    });

    test('xóa một từ khóa và xóa tất cả', () async {
      final dao = SearchHistoryDao(helper);
      await dao.add('u1', 'com ga');
      await dao.add('u1', 'pho');

      await dao.remove('u1', 'com ga');
      expect(await dao.recent('u1'), ['pho']);

      await dao.clear('u1');
      expect(await dao.recent('u1'), isEmpty);
    });
  });

  test('CHECK của SQLite chặn số lượng ngoài 1–50', () async {
    final db = await helper.database;
    final row = cartItem().toMap()
      ..remove('id')
      ..['quantity'] = 0;
    expect(() => db.insert('cart_items', row), throwsA(isA<DatabaseException>()));
  });
}
