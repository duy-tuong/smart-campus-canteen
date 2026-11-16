import '../core/utils/vn_time.dart';
import 'enums.dart';

/// Chuyển dữ liệu thô của Firebase (`Map<Object?, Object?>`, `List<Object?>`) sang kiểu JSON quen thuộc.
Object? normalizeRtdb(Object? value) => switch (value) {
  Map() => {for (final e in value.entries) '${e.key}': normalizeRtdb(e.value)},
  List() => [for (final v in value) normalizeRtdb(v)],
  _ => value,
};

/// Một món trong bản realtime của đơn (đã rút gọn: tên, số lượng, tùy chọn dạng chữ, ghi chú).
class LiveOrderItem {
  const LiveOrderItem({required this.name, required this.quantity, this.options, this.note});

  factory LiveOrderItem.fromMap(Map<String, dynamic> map) => LiveOrderItem(
    name: map['name'] as String? ?? '',
    quantity: (map['quantity'] as num?)?.toInt() ?? 1,
    options: map['options'] as String?,
    note: map['note'] as String?,
  );

  final String name;
  final int quantity;
  final String? options;
  final String? note;
}

/// Bản realtime của một đơn ở Firebase `orders/{orderId}` — backend ghi mỗi khi đơn đổi trạng thái.
/// Thời gian lưu dạng epoch mili-giây.
class OrderLive {
  const OrderLive({
    required this.id,
    required this.userId,
    required this.pickupCode,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.totalAmount,
    required this.totalItems,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.customerName,
    this.note,
    this.cancelReason,
    this.pickupTime,
    this.estimatedReadyAt,
  });

  factory OrderLive.fromMap(String id, Map<String, dynamic> map) => OrderLive(
    id: id,
    userId: map['userId'] as String? ?? '',
    customerName: map['customerName'] as String?,
    pickupCode: map['pickupCode'] as String? ?? '',
    status: OrderStatus.fromJson(map['status']),
    paymentMethod: PaymentMethod.fromJson(map['paymentMethod']),
    paymentStatus: PaymentStatus.fromJson(map['paymentStatus']),
    totalAmount: (map['totalAmount'] as num?)?.toInt() ?? 0,
    totalItems: (map['totalItems'] as num?)?.toInt() ?? 0,
    items: (map['items'] as List? ?? const []).whereType<Map<String, dynamic>>().map(LiveOrderItem.fromMap).toList(),
    note: map['note'] as String?,
    cancelReason: map['cancelReason'] as String?,
    pickupTime: VnTime.fromEpochMs(map['pickupTime']),
    estimatedReadyAt: VnTime.fromEpochMs(map['estimatedReadyAt']),
    createdAt: VnTime.fromEpochMs(map['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt: VnTime.fromEpochMs(map['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  final String id;
  final String userId;
  final String? customerName;
  final String pickupCode;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final int totalAmount;
  final int totalItems;
  final List<LiveOrderItem> items;
  final String? note;
  final String? cancelReason;
  final DateTime? pickupTime;
  final DateTime? estimatedReadyAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// "Cơm gà ×1, Trà sữa ×2"
  String get itemsPreview => items.map((i) => '${i.name} ×${i.quantity}').join(', ');
}

enum NotificationType {
  orderStatus,
  promotion,
  system,
  review;

  static NotificationType fromJson(Object? value) =>
      values.where((v) => v.name.toLowerCase() == '$value'.toLowerCase()).firstOrNull ?? system;
}

/// Thông báo trong app: realtime ở Firebase `notifications/{uid}/n{id}`, bản lâu dài ở REST /api/notifications.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.refId,
  });

  /// Từ Firebase: khóa dạng "n123" (tránh Firebase tự biến khóa số thành mảng).
  factory AppNotification.fromRtdb(String key, Map<String, dynamic> map) => AppNotification(
    id: int.tryParse(key.startsWith('n') ? key.substring(1) : key) ?? 0,
    title: map['title'] as String? ?? '',
    body: map['body'] as String? ?? '',
    type: NotificationType.fromJson(map['type']),
    refId: map['refId'] as String?,
    isRead: map['isRead'] as bool? ?? false,
    createdAt: VnTime.fromEpochMs(map['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: (json['id'] as num).toInt(),
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    type: NotificationType.fromJson(json['type']),
    refId: json['refId'] as String?,
    isRead: json['isRead'] as bool? ?? false,
    createdAt: VnTime.parse(json['createdAt'] as String),
  );

  final int id;
  final String title;
  final String body;
  final NotificationType type;

  /// Id đơn hàng (thông báo trạng thái đơn) hoặc id món/đánh giá.
  final String? refId;
  final bool isRead;
  final DateTime createdAt;

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    title: title,
    body: body,
    type: type,
    refId: refId,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
  );
}
