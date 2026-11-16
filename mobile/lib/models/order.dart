import '../core/utils/vn_time.dart';
import 'enums.dart';

class OrderItemOption {
  const OrderItemOption({required this.groupName, required this.optionName, required this.extraPrice});

  factory OrderItemOption.fromJson(Map<String, dynamic> json) => OrderItemOption(
    groupName: json['groupName'] as String? ?? '',
    optionName: json['optionName'] as String? ?? '',
    extraPrice: (json['extraPrice'] as num?)?.toInt() ?? 0,
  );

  final String groupName;
  final String optionName;
  final int extraPrice;
}

class OrderItem {
  const OrderItem({
    required this.foodName,
    required this.unitPrice,
    required this.optionsPrice,
    required this.quantity,
    required this.lineTotal,
    required this.options,
    this.id,
    this.foodId,
    this.imageUrl,
    this.note,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: (json['id'] as num?)?.toInt(),
    foodId: (json['foodId'] as num?)?.toInt(),
    foodName: json['foodName'] as String? ?? '',
    imageUrl: json['imageUrl'] as String?,
    unitPrice: (json['unitPrice'] as num?)?.toInt() ?? 0,
    optionsPrice: (json['optionsPrice'] as num?)?.toInt() ?? 0,
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    lineTotal: (json['lineTotal'] as num?)?.toInt() ?? 0,
    note: json['note'] as String?,
    options: (json['options'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(OrderItemOption.fromJson)
        .toList(),
  );

  final int? id;

  /// null nếu món đã bị xóa khỏi thực đơn (hóa đơn vẫn giữ tên/giá).
  final int? foodId;
  final String foodName;
  final String? imageUrl;
  final int unitPrice;
  final int optionsPrice;
  final int quantity;
  final int lineTotal;
  final String? note;
  final List<OrderItemOption> options;

  /// "Size L, Pudding trứng"
  String get optionsText => options.map((o) => o.optionName).join(', ');
}

class OrderStatusEvent {
  const OrderStatusEvent({
    required this.toStatus,
    required this.changedByName,
    required this.changedAt,
    this.fromStatus,
    this.note,
  });

  factory OrderStatusEvent.fromJson(Map<String, dynamic> json) => OrderStatusEvent(
    fromStatus: json['fromStatus'] == null ? null : OrderStatus.fromJson(json['fromStatus']),
    toStatus: OrderStatus.fromJson(json['toStatus']),
    changedByName: json['changedByName'] as String? ?? '',
    note: json['note'] as String?,
    changedAt: VnTime.parse(json['changedAt'] as String),
  );

  final OrderStatus? fromStatus;
  final OrderStatus toStatus;
  final String changedByName;
  final String? note;
  final DateTime changedAt;
}

/// Thông tin thanh toán; với chuyển khoản đang chờ trả có QR + thông tin tài khoản.
class PaymentInfo {
  const PaymentInfo({
    required this.method,
    required this.status,
    required this.amount,
    this.paidAt,
    this.checkoutUrl,
    this.qrCode,
    this.expiresAt,
    this.transferContent,
    this.bankBin,
    this.bankAccountNumber,
    this.bankAccountName,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) => PaymentInfo(
    method: PaymentMethod.fromJson(json['method']),
    status: PaymentStatus.fromJson(json['status']),
    amount: (json['amount'] as num?)?.toInt() ?? 0,
    paidAt: VnTime.tryParse(json['paidAt'] as String?),
    checkoutUrl: json['checkoutUrl'] as String?,
    qrCode: json['qrCode'] as String?,
    expiresAt: VnTime.tryParse(json['expiresAt'] as String?),
    transferContent: json['transferContent'] as String?,
    bankBin: json['bankBin'] as String?,
    bankAccountNumber: json['bankAccountNumber'] as String?,
    bankAccountName: json['bankAccountName'] as String?,
  );

  final PaymentMethod method;
  final PaymentStatus status;
  final int amount;
  final DateTime? paidAt;
  final String? checkoutUrl;
  final String? qrCode;
  final DateTime? expiresAt;
  final String? transferContent;
  final String? bankBin;
  final String? bankAccountNumber;
  final String? bankAccountName;

  bool get awaitingTransfer =>
      method == PaymentMethod.bankTransfer && status == PaymentStatus.pending && qrCode != null;
}

class OrderCustomer {
  const OrderCustomer({required this.id, required this.fullName, this.studentCode, this.phone});

  factory OrderCustomer.fromJson(Map<String, dynamic> json) => OrderCustomer(
    id: json['id'] as String? ?? '',
    fullName: json['fullName'] as String? ?? '',
    studentCode: json['studentCode'] as String?,
    phone: json['phone'] as String?,
  );

  final String id;
  final String fullName;
  final String? studentCode;
  final String? phone;
}

/// Một dòng trong danh sách đơn (GET /api/orders/me, GET /api/orders).
class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.pickupCode,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.totalAmount,
    required this.totalItems,
    required this.itemsPreview,
    required this.customerName,
    required this.createdAt,
    this.studentCode,
    this.pickupTime,
    this.estimatedReadyAt,
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
    id: json['id'] as String,
    pickupCode: json['pickupCode'] as String? ?? '',
    status: OrderStatus.fromJson(json['status']),
    paymentMethod: PaymentMethod.fromJson(json['paymentMethod']),
    paymentStatus: PaymentStatus.fromJson(json['paymentStatus']),
    totalAmount: (json['totalAmount'] as num?)?.toInt() ?? 0,
    totalItems: (json['totalItems'] as num?)?.toInt() ?? 0,
    itemsPreview: json['itemsPreview'] as String? ?? '',
    customerName: json['customerName'] as String? ?? '',
    studentCode: json['studentCode'] as String?,
    pickupTime: VnTime.tryParse(json['pickupTime'] as String?),
    estimatedReadyAt: VnTime.tryParse(json['estimatedReadyAt'] as String?),
    createdAt: VnTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String pickupCode;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final int totalAmount;
  final int totalItems;
  final String itemsPreview;
  final String customerName;
  final String? studentCode;
  final DateTime? pickupTime;
  final DateTime? estimatedReadyAt;
  final DateTime createdAt;
}

/// Chi tiết đơn (GET /api/orders/{id}, kết quả POST /api/orders).
class OrderDetail {
  const OrderDetail({
    required this.id,
    required this.pickupCode,
    required this.pickupDate,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.subtotal,
    required this.discountAmount,
    required this.totalAmount,
    required this.totalItems,
    required this.createdAt,
    required this.updatedAt,
    required this.customer,
    required this.items,
    required this.history,
    required this.canCancel,
    required this.allowedNextStatuses,
    this.paidAt,
    this.voucherCode,
    this.note,
    this.cancelReason,
    this.pickupTime,
    this.estimatedReadyAt,
    this.payment,
  });

  factory OrderDetail.fromJson(Map<String, dynamic> json) => OrderDetail(
    id: json['id'] as String,
    pickupCode: json['pickupCode'] as String? ?? '',
    pickupDate: json['pickupDate'] as String? ?? '',
    status: OrderStatus.fromJson(json['status']),
    paymentMethod: PaymentMethod.fromJson(json['paymentMethod']),
    paymentStatus: PaymentStatus.fromJson(json['paymentStatus']),
    paidAt: VnTime.tryParse(json['paidAt'] as String?),
    subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
    discountAmount: (json['discountAmount'] as num?)?.toInt() ?? 0,
    totalAmount: (json['totalAmount'] as num?)?.toInt() ?? 0,
    totalItems: (json['totalItems'] as num?)?.toInt() ?? 0,
    voucherCode: json['voucherCode'] as String?,
    note: json['note'] as String?,
    cancelReason: json['cancelReason'] as String?,
    pickupTime: VnTime.tryParse(json['pickupTime'] as String?),
    estimatedReadyAt: VnTime.tryParse(json['estimatedReadyAt'] as String?),
    createdAt: VnTime.parse(json['createdAt'] as String),
    updatedAt: VnTime.parse(json['updatedAt'] as String),
    customer: OrderCustomer.fromJson(json['customer'] as Map<String, dynamic>? ?? const {}),
    items: (json['items'] as List? ?? const []).whereType<Map<String, dynamic>>().map(OrderItem.fromJson).toList(),
    history: (json['history'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(OrderStatusEvent.fromJson)
        .toList(),
    payment: json['payment'] is Map<String, dynamic>
        ? PaymentInfo.fromJson(json['payment'] as Map<String, dynamic>)
        : null,
    canCancel: json['canCancel'] as bool? ?? false,
    allowedNextStatuses: (json['allowedNextStatuses'] as List? ?? const []).map(OrderStatus.fromJson).toList(),
  );

  final String id;
  final String pickupCode;

  /// Ngày nhận món theo giờ VN, dạng "2026-11-16".
  final String pickupDate;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final DateTime? paidAt;
  final int subtotal;
  final int discountAmount;
  final int totalAmount;
  final int totalItems;
  final String? voucherCode;
  final String? note;
  final String? cancelReason;
  final DateTime? pickupTime;
  final DateTime? estimatedReadyAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final OrderCustomer customer;
  final List<OrderItem> items;
  final List<OrderStatusEvent> history;
  final PaymentInfo? payment;
  final bool canCancel;
  final List<OrderStatus> allowedNextStatuses;

  /// "Cơm gà xối mỡ ×2, Trà sữa trân châu ×1" — cùng định dạng với danh sách đơn của backend.
  String get itemsPreview => items.map((i) => '${i.foodName} ×${i.quantity}').join(', ');
}
