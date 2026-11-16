import 'package:campus_canteen/data/firebase/auth_service.dart';
import 'package:campus_canteen/data/remote/order_api.dart';
import 'package:campus_canteen/models/enums.dart';
import 'package:campus_canteen/models/live.dart';
import 'package:campus_canteen/models/order.dart';
import 'package:campus_canteen/providers/orders_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_realtime.dart';
import '../support/fakes.dart';
import '../support/memory_daos.dart';

void main() {
  group('Dữ liệu Firebase → model', () {
    test('normalizeRtdb: Map<Object?,Object?> lồng nhau và List → JSON', () {
      final raw = <Object?, Object?>{
        'status': 'cooking',
        'items': <Object?>[
          <Object?, Object?>{'name': 'Cơm gà', 'quantity': 2},
        ],
      };
      final json = normalizeRtdb(raw) as Map<String, dynamic>;
      expect((json['items'] as List).first, {'name': 'Cơm gà', 'quantity': 2});
    });

    test('OrderLive: enum chuỗi camelCase, thời gian epoch ms (UTC), danh sách món', () {
      final live = OrderLive.fromMap('o1', {
        'userId': 'u1',
        'pickupCode': 'A007',
        'status': 'ready',
        'paymentMethod': 'bankTransfer',
        'paymentStatus': 'paid',
        'totalAmount': 62000,
        'totalItems': 2,
        'items': [
          {'name': 'Trà sữa', 'quantity': 2, 'options': 'L, 50%', 'note': 'Ít đá'},
        ],
        'estimatedReadyAt': DateTime.utc(2026, 11, 16, 3, 20).millisecondsSinceEpoch,
        'createdAt': DateTime.utc(2026, 11, 16, 3).millisecondsSinceEpoch,
        'updatedAt': DateTime.utc(2026, 11, 16, 3, 15).millisecondsSinceEpoch,
      });
      expect(live.status, OrderStatus.ready);
      expect(live.paymentMethod, PaymentMethod.bankTransfer);
      expect(live.estimatedReadyAt, DateTime.utc(2026, 11, 16, 3, 20));
      expect(live.itemsPreview, 'Trà sữa ×2');
      expect(live.items.single.options, 'L, 50%');
    });

    test('AppNotification: khóa "n123" → id 123; loại thông báo; mặc định chưa đọc', () {
      final n = AppNotification.fromRtdb('n123', {
        'title': 'Mời nhận món',
        'body': '...',
        'type': 'orderStatus',
        'refId': 'o1',
        'createdAt': 0,
      });
      expect(n.id, 123);
      expect(n.type, NotificationType.orderStatus);
      expect(n.isRead, isFalse);
      expect(NotificationType.fromJson('unknown'), NotificationType.system);
    });
  });

  group('OrdersProvider (offline trước)', () {
    late FakeBackend backend;
    late MemoryOrderDao dao;
    late FakeRealtimeService realtime;
    late OrdersProvider provider;

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    setUp(() async {
      backend = FakeBackend();
      dao = MemoryOrderDao();
      realtime = FakeRealtimeService();
      final api = OrderApi(backend.client(auth: FakeAuthService(signedIn: const AuthUser(uid: 'uid-sv01'))));
      provider = OrdersProvider(api: api, dao: dao, realtime: realtime);
    });

    tearDown(() => provider.dispose());

    test('đọc SQLite trước, rồi đồng bộ API ghi vào SQLite; lọc theo tab', () async {
      backend.seedOrder(status: 'received');
      backend.seedOrder(status: 'completed', createdAt: '2026-11-15T03:00:00Z');
      provider.attachUser('uid-sv01');
      await settle();
      expect(provider.isLoadedLocal, isTrue);
      expect(provider.ordersIn(OrderTab.active), isEmpty, reason: 'máy chưa có gì');

      await provider.refresh(OrderTab.active);
      await provider.refresh(OrderTab.completed);
      expect(provider.ordersIn(OrderTab.active).single.id, 'order-1');
      expect(provider.ordersIn(OrderTab.completed).single.id, 'order-2');
      expect(dao.rows.keys, containsAll(['order-1', 'order-2']), reason: 'đã lưu vào SQLite');
    });

    test('mất mạng → giữ dữ liệu trên máy + cờ offline', () async {
      backend.seedOrder();
      provider.attachUser('uid-sv01');
      await settle();
      await provider.refresh(OrderTab.active);

      backend.offline = true;
      await provider.refresh(OrderTab.active);
      expect(provider.isOffline, isTrue);
      expect(provider.ordersIn(OrderTab.active), hasLength(1));
    });

    test('Firebase báo đổi trạng thái → cập nhật SQLite và chuyển tab', () async {
      backend.seedOrder();
      provider.attachUser('uid-sv01');
      await settle();
      await provider.refresh(OrderTab.active);

      realtime.pushOrder(liveOrder('order-1', status: 'completed'));
      await settle();
      expect(dao.rows['order-1']!.status, OrderStatus.completed);
      expect(provider.ordersIn(OrderTab.active), isEmpty);
      expect(provider.ordersIn(OrderTab.completed).single.id, 'order-1');
    });

    test('xóa một hóa đơn / xóa hết trên máy', () async {
      backend.seedOrder(status: 'completed');
      backend.seedOrder(status: 'cancelled');
      provider.attachUser('uid-sv01');
      await settle();
      await provider.refresh(OrderTab.completed);
      await provider.refresh(OrderTab.cancelled);

      await provider.deleteLocal('order-1');
      expect(provider.ordersIn(OrderTab.completed), isEmpty);
      expect(await provider.clearLocal(), 1);
      expect(provider.ordersIn(OrderTab.cancelled), isEmpty);
    });

    test('đổi người dùng → xóa danh sách đang hiển thị', () async {
      backend.seedOrder();
      provider.attachUser('uid-sv01');
      await settle();
      await provider.refresh(OrderTab.active);
      provider.attachUser(null);
      expect(provider.ordersIn(OrderTab.active), isEmpty);
      expect(provider.isLoadedLocal, isFalse);
    });
  });

  test('OrderItem dùng cho Đặt lại giữ tên tùy chọn', () {
    final item = OrderItem.fromJson({
      'foodId': 2,
      'foodName': 'Trà sữa',
      'quantity': 1,
      'options': [
        {'groupName': 'Size', 'optionName': 'L', 'extraPrice': 6000},
      ],
    });
    expect(item.options.single.groupName, 'Size');
  });
}
