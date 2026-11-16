import '../core/utils/money.dart';
import '../core/utils/vn_time.dart';
import 'cart_item.dart';

/// Thông tin vận hành căn-tin (GET /api/canteen/info).
class CanteenInfo {
  const CanteenInfo({
    required this.openMinutes,
    required this.closeMinutes,
    required this.isOpen,
    required this.serverTime,
    required this.minPickupLeadMinutes,
    required this.unpaidTransferTimeoutMinutes,
    required this.maxActiveOrdersPerUser,
    required this.maxLinesPerOrder,
    required this.bankTransferEnabled,
    required this.clockSkew,
  });

  factory CanteenInfo.fromJson(Map<String, dynamic> json, {DateTime? receivedAt}) {
    final serverTime = VnTime.parse(json['serverTime'] as String);
    return CanteenInfo(
      openMinutes: _minutes(json['openTime'] as String? ?? '06:30'),
      closeMinutes: _minutes(json['closeTime'] as String? ?? '19:00'),
      isOpen: json['isOpen'] as bool? ?? true,
      serverTime: serverTime,
      minPickupLeadMinutes: (json['minPickupLeadMinutes'] as num?)?.toInt() ?? 10,
      unpaidTransferTimeoutMinutes: (json['unpaidTransferTimeoutMinutes'] as num?)?.toInt() ?? 15,
      maxActiveOrdersPerUser: (json['maxActiveOrdersPerUser'] as num?)?.toInt() ?? 3,
      maxLinesPerOrder: (json['maxLinesPerOrder'] as num?)?.toInt() ?? 20,
      bankTransferEnabled: json['bankTransferEnabled'] as bool? ?? false,
      clockSkew: serverTime.difference((receivedAt ?? DateTime.now()).toUtc()),
    );
  }

  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// Giờ mở/đóng tính bằng phút từ 0h (giờ VN).
  final int openMinutes;
  final int closeMinutes;
  final bool isOpen;
  final DateTime serverTime;
  final int minPickupLeadMinutes;
  final int unpaidTransferTimeoutMinutes;
  final int maxActiveOrdersPerUser;
  final int maxLinesPerOrder;
  final bool bankTransferEnabled;

  /// Đồng hồ máy chủ − đồng hồ điện thoại: tính giờ theo máy chủ dù điện thoại chỉnh sai giờ.
  final Duration clockSkew;

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  /// "06:30–19:00"
  String get hoursLabel => '${_hhmm(openMinutes)}–${_hhmm(closeMinutes)}';

  /// Bây giờ theo đồng hồ máy chủ (UTC).
  DateTime serverNow([DateTime? deviceNow]) => (deviceNow ?? DateTime.now()).toUtc().add(clockSkew);

  /// Khung giờ hẹn lấy món hôm nay, cách nhau [step] phút: từ (bây giờ + thời gian chuẩn bị + dự phòng)
  /// đến giờ đóng cửa. Chọn bằng chạm (không bắt gõ giờ). Máy chủ vẫn kiểm tra lại khi đặt.
  List<DateTime> pickupSlots({DateTime? deviceNow, int step = 15, int bufferMinutes = 10, int maxSlots = 16}) {
    final nowVn = VnTime.toVietnam(serverNow(deviceNow));
    final dayStartVn = DateTime.utc(nowVn.year, nowVn.month, nowVn.day);
    final nowMinutes = nowVn.hour * 60 + nowVn.minute + (nowVn.second > 0 ? 1 : 0);
    var first = nowMinutes + minPickupLeadMinutes + bufferMinutes;
    if (first < openMinutes) first = openMinutes;
    first = ((first + step - 1) ~/ step) * step; // làm tròn lên mốc 15 phút
    return [
      for (var m = first; m <= closeMinutes && m < 24 * 60; m += step)
        // Giờ VN (mốc trong ngày) → UTC để gửi máy chủ.
        dayStartVn.add(Duration(minutes: m)).subtract(VnTime.offset),
    ].take(maxSlots).toList();
  }
}

/// Một dòng giỏ hàng gửi lên máy chủ (KHÔNG gửi giá — máy chủ tự tính).
Map<String, Object?> cartLineJson(CartItem item) => {
  'foodId': item.foodId,
  'quantity': item.quantity,
  'optionIds': [for (final o in item.options) o.optionId],
  'note': item.note,
};

class PricedOption {
  const PricedOption({
    required this.optionId,
    required this.groupName,
    required this.optionName,
    required this.extraPrice,
  });

  factory PricedOption.fromJson(Map<String, dynamic> json) => PricedOption(
    optionId: (json['optionId'] as num).toInt(),
    groupName: json['groupName'] as String? ?? '',
    optionName: json['optionName'] as String? ?? '',
    extraPrice: (json['extraPrice'] as num?)?.toInt() ?? 0,
  );

  final int optionId;
  final String groupName;
  final String optionName;
  final int extraPrice;
}

/// Một dòng đã được máy chủ tính giá (giá có thể khác giá lúc thêm vào giỏ).
class PricedLine {
  const PricedLine({
    required this.index,
    required this.foodId,
    required this.foodName,
    required this.unitPrice,
    required this.optionsPrice,
    required this.quantity,
    required this.lineTotal,
    required this.options,
    this.imageUrl,
    this.note,
  });

  factory PricedLine.fromJson(Map<String, dynamic> json) => PricedLine(
    index: (json['index'] as num).toInt(),
    foodId: (json['foodId'] as num).toInt(),
    foodName: json['foodName'] as String? ?? '',
    imageUrl: json['imageUrl'] as String?,
    unitPrice: (json['unitPrice'] as num?)?.toInt() ?? 0,
    optionsPrice: (json['optionsPrice'] as num?)?.toInt() ?? 0,
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    lineTotal: (json['lineTotal'] as num?)?.toInt() ?? 0,
    note: json['note'] as String?,
    options: (json['options'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PricedOption.fromJson)
        .toList(),
  );

  /// Vị trí dòng trong giỏ đã gửi lên.
  final int index;
  final int foodId;
  final String foodName;
  final String? imageUrl;
  final int unitPrice;
  final int optionsPrice;
  final int quantity;
  final int lineTotal;
  final String? note;
  final List<PricedOption> options;

  String get optionsText => options.map((o) => o.optionName).join(', ');
}

/// Lỗi của một dòng giỏ hàng (món hết, ngừng bán, tùy chọn không còn...).
class LineError {
  const LineError({
    required this.index,
    required this.foodId,
    required this.code,
    required this.message,
    this.remaining,
  });

  factory LineError.fromJson(Map<String, dynamic> json) => LineError(
    index: (json['index'] as num).toInt(),
    foodId: (json['foodId'] as num?)?.toInt() ?? 0,
    code: json['code'] as String? ?? '',
    message: json['message'] as String? ?? '',
    remaining: (json['remaining'] as num?)?.toInt(),
  );

  final int index;
  final int foodId;
  final String code;
  final String message;

  /// Với ITEM_SOLD_OUT: số suất còn lại (> 0 thì giảm số lượng là đặt được).
  final int? remaining;

  static const soldOut = 'ITEM_SOLD_OUT';
  static const unavailable = 'ITEM_UNAVAILABLE';
  static const optionInvalid = 'OPTION_INVALID';
}

class VoucherCheck {
  const VoucherCheck({
    required this.code,
    required this.isValid,
    required this.discount,
    required this.message,
    this.errorCode,
  });

  factory VoucherCheck.fromJson(Map<String, dynamic> json) => VoucherCheck(
    code: json['code'] as String? ?? '',
    isValid: json['isValid'] as bool? ?? false,
    discount: (json['discount'] as num?)?.toInt() ?? 0,
    errorCode: json['errorCode'] as String?,
    message: json['message'] as String? ?? '',
  );

  final String code;
  final bool isValid;
  final int discount;
  final String? errorCode;
  final String message;
}

/// Báo giá giỏ hàng (POST /api/orders/quote).
class Quote {
  const Quote({
    required this.lines,
    required this.errors,
    required this.totalItems,
    required this.subtotal,
    required this.discountAmount,
    required this.totalAmount,
    required this.canOrder,
    this.voucher,
  });

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
    lines: (json['lines'] as List? ?? const []).whereType<Map<String, dynamic>>().map(PricedLine.fromJson).toList(),
    errors: (json['errors'] as List? ?? const []).whereType<Map<String, dynamic>>().map(LineError.fromJson).toList(),
    totalItems: (json['totalItems'] as num?)?.toInt() ?? 0,
    subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
    voucher: json['voucher'] is Map<String, dynamic>
        ? VoucherCheck.fromJson(json['voucher'] as Map<String, dynamic>)
        : null,
    discountAmount: (json['discountAmount'] as num?)?.toInt() ?? 0,
    totalAmount: (json['totalAmount'] as num?)?.toInt() ?? 0,
    canOrder: json['canOrder'] as bool? ?? false,
  );

  final List<PricedLine> lines;
  final List<LineError> errors;
  final int totalItems;
  final int subtotal;
  final VoucherCheck? voucher;
  final int discountAmount;
  final int totalAmount;

  /// true khi mọi dòng hợp lệ (voucher sai không chặn đặt — chỉ không được giảm).
  final bool canOrder;

  LineError? errorAt(int index) => errors.where((e) => e.index == index).firstOrNull;
}

enum DiscountType {
  percent,
  fixed;

  static DiscountType fromJson(Object? value) => '$value'.toLowerCase() == 'percent' ? percent : fixed;
}

/// Voucher tôi đang dùng được (GET /api/vouchers/available).
class AvailableVoucher {
  const AvailableVoucher({
    required this.code,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    required this.endAt,
    this.maxDiscount,
    this.remainingForMe,
  });

  factory AvailableVoucher.fromJson(Map<String, dynamic> json) => AvailableVoucher(
    code: json['code'] as String,
    description: json['description'] as String? ?? '',
    discountType: DiscountType.fromJson(json['discountType']),
    discountValue: (json['discountValue'] as num?)?.toInt() ?? 0,
    maxDiscount: (json['maxDiscount'] as num?)?.toInt(),
    minOrderAmount: (json['minOrderAmount'] as num?)?.toInt() ?? 0,
    endAt: VnTime.parse(json['endAt'] as String),
    remainingForMe: (json['remainingForMe'] as num?)?.toInt(),
  );

  final String code;
  final String description;
  final DiscountType discountType;
  final int discountValue;
  final int? maxDiscount;
  final int minOrderAmount;
  final DateTime endAt;
  final int? remainingForMe;

  /// "Giảm 10% (tối đa 15.000đ)" / "Giảm 5.000đ"
  String get title => discountType == DiscountType.percent
      ? 'Giảm $discountValue%${maxDiscount != null ? ' (tối đa ${Money.format(maxDiscount!)})' : ''}'
      : 'Giảm ${Money.format(discountValue)}';

  /// Tiền giảm ước tính cho tạm tính [subtotal] (máy chủ tính lại chính xác khi báo giá).
  int estimateFor(int subtotal) {
    if (subtotal < minOrderAmount) return 0;
    final raw = discountType == DiscountType.percent ? subtotal * discountValue ~/ 100 : discountValue;
    final capped = maxDiscount == null ? raw : (raw > maxDiscount! ? maxDiscount! : raw);
    return capped > subtotal ? subtotal : capped;
  }
}
