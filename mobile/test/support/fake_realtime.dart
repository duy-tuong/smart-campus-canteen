import 'dart:async';

import 'package:campus_canteen/data/firebase/realtime_service.dart';
import 'package:campus_canteen/models/live.dart';

/// Firebase Realtime Database giả: test "đẩy" dữ liệu như khi backend ghi lên Firebase.
class FakeRealtimeService implements RealtimeService {
  final Map<String, OrderLive?> _orders = {};
  final Map<String, StreamController<OrderLive?>> _orderStreams = {};
  final _myOrders = StreamController<List<OrderLive>>.broadcast();
  final _notifications = StreamController<List<AppNotification>>.broadcast();
  List<AppNotification> notifications = [];

  /// Số lần app đăng ký nghe từng đơn (kiểm tra không nghe trùng).
  final Map<String, int> orderListens = {};

  StreamController<OrderLive?> _streamOf(String id) =>
      _orderStreams.putIfAbsent(id, () => StreamController<OrderLive?>.broadcast());

  /// Backend vừa ghi `orders/{id}`.
  void pushOrder(OrderLive order) {
    _orders[order.id] = order;
    _streamOf(order.id).add(order);
    _myOrders.add(_orders.values.whereType<OrderLive>().toList());
  }

  void pushNotifications(List<AppNotification> items) {
    notifications = items;
    _notifications.add(items);
  }

  @override
  Stream<OrderLive?> watchOrder(String orderId) async* {
    orderListens[orderId] = (orderListens[orderId] ?? 0) + 1;
    yield _orders[orderId];
    yield* _streamOf(orderId).stream;
  }

  @override
  Stream<List<OrderLive>> watchMyOrders(String uid) async* {
    yield _orders.values.whereType<OrderLive>().toList();
    yield* _myOrders.stream;
  }

  @override
  Stream<List<AppNotification>> watchNotifications(String uid, {int limit = 50}) async* {
    yield notifications;
    yield* _notifications.stream;
  }
}

/// Bản realtime của một đơn (giống dữ liệu backend ghi lên Firebase).
OrderLive liveOrder(
  String id, {
  String status = 'received',
  String paymentMethod = 'cash',
  String paymentStatus = 'pending',
  String pickupCode = 'A001',
  String? cancelReason,
  int? estimatedReadyAtMs,
}) => OrderLive.fromMap(id, {
  'userId': 'uid-sv01',
  'pickupCode': pickupCode,
  'status': status,
  'paymentMethod': paymentMethod,
  'paymentStatus': paymentStatus,
  'totalAmount': 35000,
  'totalItems': 1,
  'items': [
    {'name': 'Cơm gà xối mỡ', 'quantity': 1, 'options': '', 'note': null},
  ],
  'cancelReason': cancelReason,
  'estimatedReadyAt': estimatedReadyAtMs,
  'createdAt': DateTime.utc(2026, 11, 16, 3).millisecondsSinceEpoch,
  'updatedAt': DateTime.utc(2026, 11, 16, 3, 5).millisecondsSinceEpoch,
});

AppNotification notification(int id, {bool isRead = false, String? orderId, String title = 'Món đã sẵn sàng'}) =>
    AppNotification.fromRtdb('n$id', {
      'title': title,
      'body': 'Đơn #A001 — mời bạn đến quầy nhận món.',
      'type': orderId == null ? 'promotion' : 'orderStatus',
      'refId': orderId,
      'isRead': isRead,
      'createdAt': DateTime.utc(2026, 11, 16, 3, id).millisecondsSinceEpoch,
    });
