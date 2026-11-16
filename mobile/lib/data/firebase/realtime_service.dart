import 'package:firebase_database/firebase_database.dart';

import '../../models/live.dart';

/// Nguồn dữ liệu realtime (Firebase Realtime Database). Backend là nơi DUY NHẤT ghi;
/// app chỉ đọc (Security Rules: `.write: false`).
abstract interface class RealtimeService {
  /// Một đơn — phát lại mỗi khi căn-tin đổi trạng thái. null = không còn trên Firebase
  /// (đơn đã xong/hủy quá 24 giờ được dọn đi; dùng dữ liệu REST/SQLite thay thế).
  Stream<OrderLive?> watchOrder(String orderId);

  /// Các đơn của tôi đang có trên Firebase (đơn đang xử lý + đơn vừa xong trong 24 giờ), mới nhất trước.
  Stream<List<OrderLive>> watchMyOrders(String uid);

  /// Thông báo của tôi, mới nhất trước.
  Stream<List<AppNotification>> watchNotifications(String uid, {int limit = 50});
}

class FirebaseRealtimeService implements RealtimeService {
  FirebaseRealtimeService(this._db);

  final FirebaseDatabase _db;

  /// Lưu đệm dữ liệu đã đọc trên máy → mất mạng ngắn vẫn hiển thị trạng thái gần nhất.
  /// Phải gọi TRƯỚC lần đọc đầu tiên.
  static void enableOfflineCache(FirebaseDatabase db) {
    db.setPersistenceEnabled(true);
    db.setPersistenceCacheSizeBytes(10 * 1024 * 1024);
  }

  @override
  Stream<OrderLive?> watchOrder(String orderId) async* {
    final ref = _db.ref('orders/$orderId')..keepSynced(true);
    await for (final event in ref.onValue) {
      final value = normalizeRtdb(event.snapshot.value);
      yield value is Map<String, dynamic> ? OrderLive.fromMap(orderId, value) : null;
    }
  }

  @override
  Stream<List<OrderLive>> watchMyOrders(String uid) async* {
    // Rules chỉ cho sinh viên đọc danh sách khi truy vấn ĐÚNG userId của mình.
    final query = _db.ref('orders').orderByChild('userId').equalTo(uid);
    await for (final event in query.onValue) {
      final value = normalizeRtdb(event.snapshot.value);
      final orders = value is Map<String, dynamic>
          ? [
              for (final e in value.entries)
                if (e.value is Map<String, dynamic>) OrderLive.fromMap(e.key, e.value as Map<String, dynamic>),
            ]
          : <OrderLive>[];
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      yield orders;
    }
  }

  @override
  Stream<List<AppNotification>> watchNotifications(String uid, {int limit = 50}) async* {
    final query = _db.ref('notifications/$uid').orderByChild('createdAt').limitToLast(limit);
    await for (final event in query.onValue) {
      final value = normalizeRtdb(event.snapshot.value);
      final items = value is Map<String, dynamic>
          ? [
              for (final e in value.entries)
                if (e.value is Map<String, dynamic>) AppNotification.fromRtdb(e.key, e.value as Map<String, dynamic>),
            ]
          : <AppNotification>[];
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      yield items;
    }
  }
}
