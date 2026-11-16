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

  /// Bảng đơn của căn-tin (chỉ staff/admin — Rules kiểm tra claim `role` trong token):
  /// mọi đơn đang có trên Firebase, cũ nhất trước (đơn đặt trước làm trước).
  Stream<List<OrderLive>> watchBoard();
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

  // Mọi stream viết bằng async* + `yield*` (KHÔNG dùng `await for`): `yield*` chuyển lệnh hủy xuống stream
  // của Firebase NGAY khi màn hình thôi nghe. Với `await for`, listener chỉ được hủy ở lần `yield` kế tiếp —
  // Firebase sống lâu nên listener treo lại; khi đăng xuất, lỗi permission-denied rơi vào generator đã hủy
  // thành "Unhandled Exception" (đã gặp khi chạy thật).

  @override
  Stream<OrderLive?> watchOrder(String orderId) async* {
    yield* _db.ref('orders/$orderId').onValue.map((event) {
      final value = normalizeRtdb(event.snapshot.value);
      return value is Map<String, dynamic> ? OrderLive.fromMap(orderId, value) : null;
    });
  }

  @override
  Stream<List<OrderLive>> watchMyOrders(String uid) async* {
    // Rules chỉ cho sinh viên đọc danh sách khi truy vấn ĐÚNG userId của mình.
    yield* _db
        .ref('orders')
        .orderByChild('userId')
        .equalTo(uid)
        .onValue
        .map((event) => _orders(event)..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  @override
  Stream<List<AppNotification>> watchNotifications(String uid, {int limit = 50}) async* {
    yield* _db.ref('notifications/$uid').orderByChild('createdAt').limitToLast(limit).onValue.map((event) {
      final value = normalizeRtdb(event.snapshot.value);
      final items = value is Map<String, dynamic>
          ? [
              for (final e in value.entries)
                if (e.value is Map<String, dynamic>) AppNotification.fromRtdb(e.key, e.value as Map<String, dynamic>),
            ]
          : <AppNotification>[];
      return items..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  @override
  Stream<List<OrderLive>> watchBoard() async* {
    yield* _db.ref('orders').onValue.map((event) => _orders(event)..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  }

  static List<OrderLive> _orders(DatabaseEvent event) {
    final value = normalizeRtdb(event.snapshot.value);
    return value is Map<String, dynamic>
        ? [
            for (final e in value.entries)
              if (e.value is Map<String, dynamic>) OrderLive.fromMap(e.key, e.value as Map<String, dynamic>),
          ]
        : <OrderLive>[];
  }
}
